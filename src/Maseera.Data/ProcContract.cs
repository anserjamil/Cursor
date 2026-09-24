using System.Collections.Concurrent;
using System.Data;
using Dapper;
using Microsoft.Extensions.Logging;

namespace Maseera.Data;

/// <summary>
/// What each procedure's parameters are, read once from cfg.usp_Proc_Contract.
///
/// The runner adds @LoginName and @AsOf so a developer cannot forget them — but adding
/// them to a procedure that does not declare them is an error, so it has to know which
/// procedures take them. It asks the database rather than holding a list, and it asks
/// through a procedure rather than with SQL text, because there is no SQL text in C#.
/// </summary>
public interface IProcContract
{
    bool Declares(string procName, string parameterName);
    IReadOnlyCollection<string> Parameters(string procName);
    bool Exists(string procName);
    Task EnsureLoadedAsync(CancellationToken ct = default);
    void Invalidate();
}

public sealed class ProcContract : IProcContract
{
    private readonly ISqlConnectionFactory _factory;
    private readonly ILogger<ProcContract> _log;
    private readonly SemaphoreSlim _gate = new(1, 1);

    private ConcurrentDictionary<string, HashSet<string>>? _byProc;

    public ProcContract(ISqlConnectionFactory factory, ILogger<ProcContract> log)
    {
        _factory = factory;
        _log = log;
    }

    public void Invalidate() => _byProc = null;

    public async Task EnsureLoadedAsync(CancellationToken ct = default)
    {
        if (_byProc is not null) return;

        await _gate.WaitAsync(ct);
        try
        {
            if (_byProc is not null) return;

            await using var cn = _factory.Create();
            var rows = await cn.QueryAsync<ContractRow>(
                new CommandDefinition("cfg.usp_Proc_Contract",
                    commandType: CommandType.StoredProcedure, cancellationToken: ct));

            var map = new ConcurrentDictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
            foreach (var r in rows)
            {
                var set = map.GetOrAdd(r.ProcName, _ => new HashSet<string>(StringComparer.OrdinalIgnoreCase));
                if (!string.IsNullOrEmpty(r.ParameterName)) set.Add(r.ParameterName.TrimStart('@'));
            }

            _byProc = map;
            _log.LogInformation("Procedure contract loaded: {Count} procedures.", map.Count);
        }
        finally
        {
            _gate.Release();
        }
    }

    public bool Declares(string procName, string parameterName)
        => _byProc is not null
           && _byProc.TryGetValue(procName, out var set)
           && set.Contains(parameterName.TrimStart('@'));

    public IReadOnlyCollection<string> Parameters(string procName)
        => _byProc is not null && _byProc.TryGetValue(procName, out var set)
            ? set
            : Array.Empty<string>();

    public bool Exists(string procName) => _byProc?.ContainsKey(procName) == true;

    private sealed record ContractRow(string ProcName, string SchemaName, string ObjectName,
        string? ParameterName, string? TypeName, short? MaxLength, bool? IsOutput,
        bool? HasDefault, bool? IsTableType, int? OrdinalPos);
}
