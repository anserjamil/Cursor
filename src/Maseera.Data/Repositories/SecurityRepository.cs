using Dapper;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class SecurityRepository
{
    private readonly IProcRunner _run;

    public SecurityRepository(IProcRunner run) => _run = run;

    /// <summary>
    /// Resolved once per request into IUserContext. The login is passed explicitly rather
    /// than taken from the context, because this is the call that builds the context.
    /// </summary>
    public Task<UserContextRow?> ContextAsync(string loginName, DateOnly? asOf = null, CancellationToken ct = default)
        => _run.OneAsync<UserContextRow>("sec.usp_User_Context",
            new { LoginName = loginName, AsOf = asOf }, ct);

    /// <summary>Roles, screens and the grant matrix. "No grant" is a visible third state.</summary>
    public Task<(IReadOnlyList<RoleRow> Roles, IReadOnlyList<PolicyScreenRow> Screens, IReadOnlyList<PolicyGrantRow> Grants)>
        PolicyMatrixAsync(CancellationToken ct = default)
        => _run.MultiAsync("sec.usp_Policy_Matrix", async g =>
        {
            var roles = (await g.ReadAsync<RoleRow>()).AsList();
            var screens = (await g.ReadAsync<PolicyScreenRow>()).AsList();
            var grants = (await g.ReadAsync<PolicyGrantRow>()).AsList();
            return ((IReadOnlyList<RoleRow>)roles, (IReadOnlyList<PolicyScreenRow>)screens,
                    (IReadOnlyList<PolicyGrantRow>)grants);
        }, ct: ct);

    public Task<(IReadOnlyList<AppUserRow> Users, IReadOnlyList<UserOverrideRow> Overrides)>
        UsersAsync(string? search = null, CancellationToken ct = default)
        => _run.MultiAsync("sec.usp_User_List", async g =>
        {
            var users = (await g.ReadAsync<AppUserRow>()).AsList();
            var overrides = (await g.ReadAsync<UserOverrideRow>()).AsList();
            return ((IReadOnlyList<AppUserRow>)users, (IReadOnlyList<UserOverrideRow>)overrides);
        }, new { Search = search }, ct);

    /// <summary>What each screen resolves to for one login, and which rule decided it.</summary>
    public Task<IReadOnlyList<ScreenAccessExplainRow>> ExplainAsync(
        string targetLogin, DateOnly? asOf = null, CancellationToken ct = default)
        => _run.ListAsync<ScreenAccessExplainRow>("sec.usp_ScreenAccess_Explain",
            new { TargetLogin = targetLogin, AsOf = asOf }, ct);

    public Task<IReadOnlyList<OrgTreeRow>> OrgTreeAsync(string? compareLogin = null, CancellationToken ct = default)
        => _run.ListAsync<OrgTreeRow>("sel.usp_Org_Tree", new { CompareLogin = compareLogin }, ct);

    public Task<IReadOnlyList<RlsCompareRow>> CompareScopesAsync(
        string loginA, string loginB, CancellationToken ct = default)
        => _run.ListAsync<RlsCompareRow>("sec.usp_Rls_Compare", new { LoginA = loginA, LoginB = loginB }, ct);

    public Task<IReadOnlyList<DirectoryPersonRow>> SearchDirectoryAsync(
        string? search, int top = 20, CancellationToken ct = default)
        => _run.ListAsync<DirectoryPersonRow>("sel.usp_Directory_Search",
            new { Search = search, Top = top }, ct);
}
