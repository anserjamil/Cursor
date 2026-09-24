namespace Maseera.Core;

/// <summary>
/// What a procedure that can refuse gives back.
///
/// Problem non-null means the write did not happen and the sentence explains why. It is
/// rendered as a toast or a refusal panel; it is never an exception, because a refusal is
/// a designed state and not a failure.
/// </summary>
public sealed record ProcResult(bool Ok, string? Problem, int Affected, long? NewId)
{
    public static ProcResult Success(int affected = 0, long? newId = null)
        => new(true, null, affected, newId);

    public static ProcResult Refused(string problem) => new(false, problem, 0, null);
}

/// <summary>A procedure result that also carries the rows it returned.</summary>
public sealed record ProcResult<T>(bool Ok, string? Problem, IReadOnlyList<T> Rows)
{
    public T? First => Rows.Count > 0 ? Rows[0] : default;

    public static ProcResult<T> Success(IReadOnlyList<T> rows) => new(true, null, rows);

    public static ProcResult<T> Refused(string problem) => new(false, problem, Array.Empty<T>());
}
