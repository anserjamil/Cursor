using Dapper;
using Maseera.Core;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class RosterRepository
{
    private readonly IProcRunner _run;

    public RosterRepository(IProcRunner run) => _run = run;

    /// <summary>
    /// A server-paged read of the mapped roster. Problem is non-null when the question
    /// could not be asked at all — a sensitive column used as a sort, most often — and
    /// the view says so rather than showing an empty table.
    /// </summary>
    public async Task<(IReadOnlyList<PoolPersonRow> Rows, int TotalRows, string? Problem)> RosterAsync(
        string? search, string? orgCode, string? sortBy, string? sortDir,
        int pageNo, int? pageSize, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Employee_Roster", async g =>
        {
            var rows = (await g.ReadAsync<PoolPersonRow>()).AsList();
            var total = await g.ReadFirstOrDefaultAsync<int?>() ?? 0;
            return ((IReadOnlyList<PoolPersonRow>)rows, total);
        }, new
        {
            Search = search, OrgCode = orgCode, SortBy = sortBy, SortDir = sortDir,
            PageNo = pageNo, PageSize = pageSize
        }, ct);

        return (value.Item1, value.Item2, problem);
    }

    /* ---- roster fields ---------------------------------------------------------- */

    public Task<(IReadOnlyList<RosterFieldRow> Fields, RosterFieldSummary Summary)> FieldsAsync(
        string? search = null, bool enabledOnly = false, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_RosterField_List", async g =>
        {
            var fields = (await g.ReadAsync<RosterFieldRow>()).AsList();
            var summary = await g.ReadFirstOrDefaultAsync<RosterFieldSummary>()
                          ?? new RosterFieldSummary(0, 0, 0, 0);
            return ((IReadOnlyList<RosterFieldRow>)fields, summary);
        }, new { Search = search, EnabledOnly = enabledOnly }, ct);

    public Task<ProcResult> SaveFieldAsync(
        int rosterFieldId, string? caption, bool? isEnabled, bool? isSensitive,
        string? groupName, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_RosterField_Save", new
        {
            RosterFieldId = rosterFieldId, Caption = caption,
            IsEnabled = isEnabled, IsSensitive = isSensitive, GroupName = groupName
        }, ct);

    public Task<ProcResult> SyncFieldsAsync(CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_RosterField_Sync", ct: ct);

    /* ---- table mapping ---------------------------------------------------------- */

    public Task<(IReadOnlyList<TableMappingRow> Tables, IReadOnlyList<TableMappingColumnRow> Columns)>
        MappingAsync(CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_TableMapping_List", async g =>
        {
            var tables = (await g.ReadAsync<TableMappingRow>()).AsList();
            var columns = (await g.ReadAsync<TableMappingColumnRow>()).AsList();
            return ((IReadOnlyList<TableMappingRow>)tables, (IReadOnlyList<TableMappingColumnRow>)columns);
        }, ct: ct);

    public Task<ProcResult> DiscoverMappingAsync(string? sourceKey = null, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_TableMapping_Discover", new { SourceKey = sourceKey }, ct);

    public Task<ProcResult> SaveMappingAsync(
        string sourceKey, string schemaName, string tableName,
        string? keyColumn, string? itemColumn, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_TableMapping_Save", new
        {
            SourceKey = sourceKey, SchemaName = schemaName, TableName = tableName,
            KeyColumn = keyColumn, ItemColumn = itemColumn
        }, ct);

    /* ---- load exceptions -------------------------------------------------------- */

    public Task<(IReadOnlyList<LoadExceptionRow> Rows, int TotalRows, IReadOnlyList<(string SourceKey, int Unresolved)> BySource)>
        LoadExceptionsAsync(string? sourceKey, bool includeResolved, string? search,
            int pageNo, int? pageSize, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_LoadException_List", async g =>
        {
            var rows = (await g.ReadAsync<LoadExceptionRow>()).AsList();
            var total = await g.ReadFirstOrDefaultAsync<int?>() ?? 0;
            var bySource = (await g.ReadAsync<SourceCount>()).AsList()
                .Select(x => (x.SourceKey, x.Unresolved)).ToList();
            return ((IReadOnlyList<LoadExceptionRow>)rows, total,
                    (IReadOnlyList<(string, int)>)bySource);
        }, new
        {
            SourceKey = sourceKey, IncludeResolved = includeResolved,
            Search = search, PageNo = pageNo, PageSize = pageSize
        }, ct);

    public Task<ProcResult> ResolveExceptionAsync(long loadExceptionId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_LoadException_Resolve", new { LoadExceptionId = loadExceptionId }, ct);

    public Task<ProcResult> SaveAliasAsync(
        string sourceKey, string aliasKey, string personnelNo, string? note, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_PersonAlias_Save", new
        {
            SourceKey = sourceKey, AliasKey = aliasKey, PersonnelNo = personnelNo, Note = note
        }, ct);

    /* ---- loads ------------------------------------------------------------------ */

    public Task<ProcResult> LoadRosterAsync(CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Roster_Load", ct: ct);

    public Task<ProcResult> SyncEvidenceAsync(CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Evidence_SyncAll", ct: ct);

    public Task<ProcResult> RefreshMetricsAsync(CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Metric_Refresh", ct: ct);

    public Task<ProcResult> RebuildOrgAsync(CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Org_RebuildAncestors", ct: ct);

    /* ---- the column catalogue and saved views ----------------------------------- */

    public Task<(IReadOnlyList<ColumnCatalogRow> Columns, IReadOnlyList<SavedViewRow> Views)>
        ColumnCatalogAsync(string? screenCode = null, string? search = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Column_Catalog", async g =>
        {
            var cols = (await g.ReadAsync<ColumnCatalogRow>()).AsList();
            var views = (await g.ReadAsync<SavedViewRow>()).AsList();
            return ((IReadOnlyList<ColumnCatalogRow>)cols, (IReadOnlyList<SavedViewRow>)views);
        }, new { ScreenCode = screenCode, Search = search }, ct);

    public Task<ProcResult> SaveViewAsync(
        string screenCode, string viewName, string columnList, string? sortBy, string? sortDir,
        bool asPreset, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_SavedView_Save", new
        {
            ScreenCode = screenCode, ViewName = viewName, ColumnList = columnList,
            SortBy = sortBy, SortDir = sortDir, AsPreset = asPreset
        }, ct);

    public Task<ProcResult> ResetViewAsync(string screenCode, string viewName, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_SavedView_Reset", new { ScreenCode = screenCode, ViewName = viewName }, ct);

    private sealed record SourceCount(string SourceKey, int Unresolved);
}
