using Dapper;
using Maseera.Core;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

/// <summary>
/// A thin wrapper over the named procedures of the configuration engine.
///
/// Every repository in this project is this shape: it names procedures and maps rows.
/// It contains no rule, no predicate and no decision. If a method here looks like it is
/// about to make one, the procedure it wanted is missing.
/// </summary>
public sealed class ConfigRepository
{
    private readonly IProcRunner _run;

    public ConfigRepository(IProcRunner run) => _run = run;

    public Task<IReadOnlyList<HealthRow>> HealthAsync(CancellationToken ct = default)
        => _run.ListAsync<HealthRow>("cfg.usp_Health_Check", ct: ct);

    public Task<ConfigStamp?> StampAsync(CancellationToken ct = default)
        => _run.OneAsync<ConfigStamp>("cfg.usp_Config_Stamp", ct: ct);

    public Task<IReadOnlyList<SettingRow>> SettingsAsync(CancellationToken ct = default)
        => _run.ListAsync<SettingRow>("cfg.usp_Setting_List", ct: ct);

    public Task<IReadOnlyList<MessageRow>> MessagesAsync(CancellationToken ct = default)
        => _run.ListAsync<MessageRow>("cfg.usp_Message_List", ct: ct);

    public Task<IReadOnlyList<OperatorRow>> OperatorsAsync(string? dataType = null, CancellationToken ct = default)
        => _run.ListAsync<OperatorRow>("cfg.usp_Operator_List", new { DataType = dataType }, ct);

    public Task<IReadOnlyList<DomainRow>> DomainsAsync(CancellationToken ct = default)
        => _run.ListAsync<DomainRow>("cfg.usp_Domain_List", ct: ct);

    public Task<IReadOnlyList<DomainValueRow>> DomainValuesAsync(string domainCode, CancellationToken ct = default)
        => _run.ListAsync<DomainValueRow>("cfg.usp_DomainValue_List", new { DomainCode = domainCode }, ct);

    public Task<IReadOnlyList<ScreenRow>> ScreensAsync(bool includeAll = false, CancellationToken ct = default)
        => _run.ListAsync<ScreenRow>("cfg.usp_Screen_List", new { IncludeAll = includeAll }, ct);

    /// <summary>
    /// The registry as the registry, not as one viewer sees it.
    ///
    /// cfg.usp_Screen_List filters on sec.fn_ScreenAccess when it is given a login, which
    /// is right for the navigation and wrong for the self-check: the question there is
    /// whether every registered screen resolves to an action, not whether whoever happens
    /// to be asking may open it. Passing the login as null explicitly is what turns the
    /// filter off — the runner only supplies it when the caller has not.
    /// </summary>
    public Task<IReadOnlyList<ScreenRow>> AllScreensAsync(CancellationToken ct = default)
        => _run.ListAsync<ScreenRow>("cfg.usp_Screen_List",
            new { LoginName = (string?)null, IncludeAll = true }, ct);

    /// <summary>The navigation, as the TopNav view component renders it.</summary>
    public Task<(IReadOnlyList<MenuGroupRow> Groups, IReadOnlyList<ScreenRow> Screens)> MenuAsync(
        CancellationToken ct = default)
        => _run.MultiAsync("cfg.usp_Menu", async g =>
        {
            var groups = (await g.ReadAsync<MenuGroupRow>()).AsList();
            var screens = (await g.ReadAsync<ScreenRow>()).AsList();
            return ((IReadOnlyList<MenuGroupRow>)groups, (IReadOnlyList<ScreenRow>)screens);
        }, ct: ct);

    public Task<ProcResult> SaveDomainValueAsync(
        string domainCode, int? domainValueId, string valueCode, string name,
        string? description, string? semanticRole, int? sortOrder, bool isActive,
        CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_DomainValue_Save", new
        {
            DomainCode = domainCode, DomainValueId = domainValueId, ValueCode = valueCode,
            Name = name, Description = description, SemanticRole = semanticRole,
            SortOrder = sortOrder, IsActive = isActive
        }, ct);

    public Task<ProcResult> DeleteDomainValueAsync(int domainValueId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_DomainValue_Delete", new { DomainValueId = domainValueId }, ct);

    public Task<IReadOnlyList<CatalogItemRow>> CatalogAsync(
        string? kindCode = null, string? search = null, bool needsReviewOnly = false,
        CancellationToken ct = default)
        => _run.ListAsync<CatalogItemRow>("sel.usp_CatalogItem_List",
            new { KindCode = kindCode, Search = search, NeedsReviewOnly = needsReviewOnly }, ct);

    public Task<ProcResult> SaveCatalogItemAsync(
        int? catalogItemId, string itemCode, string name, string kindCode,
        string? categoryCode, bool needsReview, bool isActive, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CatalogItem_Save", new
        {
            CatalogItemId = catalogItemId, ItemCode = itemCode, Name = name, KindCode = kindCode,
            CategoryCode = categoryCode, NeedsReview = needsReview, IsActive = isActive
        }, ct);

    public Task<ProcResult> DeleteCatalogItemAsync(int catalogItemId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CatalogItem_Delete", new { CatalogItemId = catalogItemId }, ct);
}
