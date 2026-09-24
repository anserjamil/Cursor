using System.Data;
using Dapper;
using Maseera.Core;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Maseera.Data;

/// <summary>
/// The only way the application talks to the database.
///
/// Every call is a stored procedure. There is no SQL text in C#, not even a SELECT 1 —
/// the health check calls a procedure too. @LoginName and @AsOf are added from the user
/// context so a developer cannot forget them, and @Problem is read back so a refusal
/// comes home as a sentence rather than as an exception.
/// </summary>
public interface IProcRunner
{
    Task<IReadOnlyList<T>> ListAsync<T>(string proc, object? args = null, CancellationToken ct = default);
    Task<T?> OneAsync<T>(string proc, object? args = null, CancellationToken ct = default);
    Task<ProcResult> ExecAsync(string proc, object? args = null, CancellationToken ct = default);
    Task<T> MultiAsync<T>(string proc, Func<SqlMapper.GridReader, Task<T>> read, object? args = null, CancellationToken ct = default);

    /// <summary>A read that can also refuse: the rows, plus the sentence when there are none.</summary>
    Task<ProcResult<T>> ListWithProblemAsync<T>(string proc, object? args = null, CancellationToken ct = default);

    /// <summary>A multi-result read that can refuse.</summary>
    Task<(T Value, string? Problem)> MultiWithProblemAsync<T>(
        string proc, Func<SqlMapper.GridReader, Task<T>> read, object? args = null, CancellationToken ct = default);
}

public sealed class ProcRunner : IProcRunner
{
    /// <summary>The output parameter every procedure that can refuse declares.</summary>
    public const string ProblemParameter = "Problem";
    private const string LoginParameter = "LoginName";
    private const string AsOfParameter = "AsOf";
    private const string TestModeParameter = "TestMode";

    private const int DeadlockVictim = 1205;
    private const int CannotOpenDatabase = 4060;
    private const int TransientResourceLimit = 40197;

    private readonly ISqlConnectionFactory _factory;
    private readonly IUserContext _user;
    private readonly IProcContract _contract;
    private readonly MaseeraOptions _options;
    private readonly ILogger<ProcRunner> _log;

    public ProcRunner(
        ISqlConnectionFactory factory,
        IUserContext user,
        IProcContract contract,
        IOptions<MaseeraOptions> options,
        ILogger<ProcRunner> log)
    {
        _factory = factory;
        _user = user;
        _contract = contract;
        _options = options.Value;
        _log = log;
    }

    public async Task<IReadOnlyList<T>> ListAsync<T>(string proc, object? args = null, CancellationToken ct = default)
    {
        var (rows, problem) = await ReadListAsync<T>(proc, args, ct);
        if (problem is not null)
            _log.LogInformation("{Proc} refused: {Problem}", proc, problem);
        return rows;
    }

    public async Task<ProcResult<T>> ListWithProblemAsync<T>(string proc, object? args = null, CancellationToken ct = default)
    {
        var (rows, problem) = await ReadListAsync<T>(proc, args, ct);
        return problem is null ? ProcResult<T>.Success(rows) : new ProcResult<T>(false, problem, rows);
    }

    public async Task<T?> OneAsync<T>(string proc, object? args = null, CancellationToken ct = default)
    {
        var (rows, _) = await ReadListAsync<T>(proc, args, ct);
        return rows.Count > 0 ? rows[0] : default;
    }

    public async Task<ProcResult> ExecAsync(string proc, object? args = null, CancellationToken ct = default)
    {
        return await RunAsync(proc, args, isWrite: true, ct, async (cn, p) =>
        {
            // A write's result set is what changed, which the caller may or may not want.
            // Reading it fully still matters: MultipleActiveResultSets is off, so the
            // reader has to be finished before anything else uses the connection.
            var affected = 0;
            await using (var reader = await cn.ExecuteReaderAsync(Command(proc, p, ct)))
            {
                do { while (await reader.ReadAsync(ct)) affected++; }
                while (await reader.NextResultAsync(ct));
            }

            var problem = Problem(p);
            return problem is null
                ? ProcResult.Success(affected, NewId(p))
                : ProcResult.Refused(problem);
        });
    }

    public async Task<T> MultiAsync<T>(string proc, Func<SqlMapper.GridReader, Task<T>> read,
        object? args = null, CancellationToken ct = default)
    {
        var (value, _) = await MultiWithProblemAsync(proc, read, args, ct);
        return value;
    }

    public async Task<(T Value, string? Problem)> MultiWithProblemAsync<T>(
        string proc, Func<SqlMapper.GridReader, Task<T>> read, object? args = null, CancellationToken ct = default)
    {
        return await RunAsync(proc, args, isWrite: false, ct, async (cn, p) =>
        {
            // MultipleActiveResultSets=False means one open reader at a time: the grid is
            // read fully and each set materialised before the next call.
            T value;
            await using (var grid = await cn.QueryMultipleAsync(Command(proc, p, ct)))
            {
                value = await read(grid);
            }
            return (value, Problem(p));
        });
    }

    /* ------------------------------------------------------------------------------ */

    private async Task<(IReadOnlyList<T> Rows, string? Problem)> ReadListAsync<T>(
        string proc, object? args, CancellationToken ct)
    {
        return await RunAsync(proc, args, isWrite: false, ct, async (cn, p) =>
        {
            var rows = (await cn.QueryAsync<T>(Command(proc, p, ct))).AsList();
            return ((IReadOnlyList<T>)rows, Problem(p));
        });
    }

    /// <summary>
    /// Opens the connection, builds the parameters, and retries once on a deadlock or a
    /// transient failure. A write is never retried unless the caller has said it is safe,
    /// because a repeated decision is a second row in the log.
    /// </summary>
    private async Task<TResult> RunAsync<TResult>(
        string proc, object? args, bool isWrite, CancellationToken ct,
        Func<SqlConnection, DynamicParameters, Task<TResult>> body)
    {
        await _contract.EnsureLoadedAsync(ct);

        if (!_contract.Exists(proc))
        {
            // A missing procedure is a deployment problem, and saying so plainly is far
            // more useful than the SQL error about an unknown object.
            throw new InvalidOperationException(
                $"The procedure '{proc}' is not in the database. Run the migrations in db/ against DB02.");
        }

        var attempt = 0;
        while (true)
        {
            attempt++;
            try
            {
                var p = BuildParameters(proc, args);
                await using var cn = _factory.Create();
                await cn.OpenAsync(ct);
                return await body(cn, p);
            }
            catch (SqlException ex) when (attempt == 1 && !isWrite && IsRetryable(ex))
            {
                _log.LogWarning(ex, "{Proc} hit SQL error {Number}; retrying once.", proc, ex.Number);
                await Task.Delay(250, ct);
            }
        }
    }

    private static bool IsRetryable(SqlException ex)
        => ex.Number is DeadlockVictim or CannotOpenDatabase or TransientResourceLimit;

    private CommandDefinition Command(string proc, DynamicParameters p, CancellationToken ct)
        => new(proc, p,
            commandType: CommandType.StoredProcedure,
            commandTimeout: _options.CommandTimeoutSeconds,
            cancellationToken: ct);

    /// <summary>
    /// Whatever the caller passed, plus the three things every screen needs and nobody
    /// should have to remember — but only where the procedure actually declares them.
    /// </summary>
    private DynamicParameters BuildParameters(string proc, object? args)
    {
        var p = args is null ? new DynamicParameters() : new DynamicParameters(args);

        // Read what the caller supplied off the object itself, not off
        // DynamicParameters.ParameterNames. An object passed to the constructor is kept
        // as a template and is not enumerated there, so ParameterNames comes back empty
        // and every caller's own @LoginName, @AsOf or @TestMode would be silently
        // overwritten by the ambient one below — which is exactly the kind of quiet
        // override that makes a screen disagree with the database.
        var given = GivenNames(args);

        if (_contract.Declares(proc, LoginParameter) && !given.Contains(LoginParameter))
            p.Add(LoginParameter, _user.LoginName, DbType.String, size: 128);

        if (_contract.Declares(proc, AsOfParameter) && !given.Contains(AsOfParameter))
            p.Add(AsOfParameter, _user.AsOf, DbType.Date);

        if (_contract.Declares(proc, TestModeParameter) && !given.Contains(TestModeParameter))
            p.Add(TestModeParameter, _user.TestMode, DbType.Boolean);

        // A refusal comes back as a sentence, so the output has to be there to receive it.
        if (_contract.Declares(proc, ProblemParameter) && !given.Contains(ProblemParameter))
            p.Add(ProblemParameter, dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        return p;
    }

    /// <summary>
    /// The parameter names the caller actually passed. Handles a plain object, a
    /// DynamicParameters the caller built itself, and a dictionary.
    /// </summary>
    private static HashSet<string> GivenNames(object? args)
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (args is null) return names;

        if (args is DynamicParameters dynamic)
        {
            foreach (var name in dynamic.ParameterNames) names.Add(name);
            return names;
        }

        if (args is IDictionary<string, object?> dictionary)
        {
            foreach (var key in dictionary.Keys) names.Add(key);
            return names;
        }

        foreach (var property in args.GetType().GetProperties())
            names.Add(property.Name);

        return names;
    }

    private static string? Problem(DynamicParameters p)
    {
        if (!p.ParameterNames.Contains(ProblemParameter, StringComparer.OrdinalIgnoreCase))
            return null;

        var text = p.Get<string?>(ProblemParameter);
        return string.IsNullOrWhiteSpace(text) ? null : text;
    }

    private static long? NewId(DynamicParameters p)
        => p.ParameterNames.Contains("NewId", StringComparer.OrdinalIgnoreCase)
            ? p.Get<long?>("NewId")
            : null;
}
