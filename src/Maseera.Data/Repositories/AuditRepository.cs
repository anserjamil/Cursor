using Dapper;

namespace Maseera.Data.Repositories;

/// <summary>
/// The configuration change log. Append only — nothing in the application deletes from
/// audit.ChangeLog, so there is a read here and no write.
/// </summary>
public sealed class AuditRepository
{
    private readonly IProcRunner _run;

    public AuditRepository(IProcRunner run) => _run = run;

    public Task<ChangeLogPage> ChangesAsync(
        string? tableName = null, string? actorLogin = null, string? search = null,
        int pageNo = 1, int? pageSize = null, CancellationToken ct = default)
        => _run.MultiAsync("audit.usp_ChangeLog_List", async g =>
        {
            var rows = (await g.ReadAsync<ChangeLogRow>()).AsList();
            var total = await g.ReadFirstOrDefaultAsync<int?>() ?? 0;
            var byTable = (await g.ReadAsync<ChangeLogTableRow>()).AsList();
            return new ChangeLogPage(rows, total, byTable);
        }, new
        {
            TableName = tableName, ActorLogin = actorLogin, Search = search,
            PageNo = pageNo, PageSize = pageSize
        }, ct);
}

public sealed record ChangeLogRow(
    long ChangeLogId, string TableName, string? KeyText, string ActionCode,
    string? BeforeJson, string? AfterJson, string LoginName, DateTime ChangedOnUtc,
    string? ActorName);

public sealed record ChangeLogTableRow(string TableName, int Changes);

public sealed record ChangeLogPage(
    IReadOnlyList<ChangeLogRow> Rows, int TotalRows, IReadOnlyList<ChangeLogTableRow> ByTable);
