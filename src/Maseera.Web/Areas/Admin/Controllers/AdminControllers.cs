using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Maseera.Web.Startup;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Admin.Controllers;

/// <summary>
/// Roles, users, screens and the grant matrix — with the six-rule precedence rendered as
/// a numbered list, so a denial is explainable rather than mysterious.
/// </summary>
[Area("Admin")]
public sealed class PolicyController : MaseeraController
{
    public const string Screen = "/Admin/Policy/";

    private readonly SecurityRepository _security;

    public PolicyController(SecurityRepository security) => _security = security;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(string? explain = null, string? q = null, CancellationToken ct = default)
    {
        var (roles, screens, grants) = await _security.PolicyMatrixAsync(ct);
        var (users, overrides) = await _security.UsersAsync(q, ct);

        return View(new PolicyViewModel
        {
            Roles = roles,
            Screens = screens,
            Grants = grants.ToDictionary(g => (g.RoleId, g.ScreenId), g => g.GrantValue),
            Users = users,
            Overrides = overrides,
            ExplainLogin = explain,
            Explanation = explain is null ? [] : await _security.ExplainAsync(explain, ct: ct),
            Search = q,
            CanWrite = CanWrite
        });
    }
}

/// <summary>
/// The organisation tree with Granted / Not granted per node, and a comparison of two
/// viewers' scopes. Two people looking at the same cycle legitimately see different
/// people in it, and this is where that is made visible.
/// </summary>
[Area("Admin")]
public sealed class RlsController : MaseeraController
{
    public const string Screen = "/Admin/Policy/";

    private readonly SecurityRepository _security;

    public RlsController(SecurityRepository security) => _security = security;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        string? viewer = null, string? compare = null, CancellationToken ct = default)
    {
        viewer ??= User_.LoginName;

        var tree = await _security.OrgTreeAsync(compare, ct);
        var (users, _) = await _security.UsersAsync(ct: ct);

        var comparison = compare is null
            ? []
            : await _security.CompareScopesAsync(viewer, compare, ct);

        return View(new RlsViewModel
        {
            Tree = tree, Users = users, Viewer = viewer,
            CompareWith = compare, Comparison = comparison
        });
    }
}

/// <summary>
/// The difference between a wrong number somebody catches and a wrong number nobody does.
/// </summary>
[Area("Admin")]
public sealed class LoadExceptionsController : MaseeraController
{
    public const string Screen = "/Admin/Policy/";

    private readonly RosterRepository _roster;

    public LoadExceptionsController(RosterRepository roster) => _roster = roster;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        string? source = null, bool includeResolved = false, string? q = null,
        int page = 1, int? size = null, CancellationToken ct = default)
    {
        var (rows, total, bySource) = await _roster.LoadExceptionsAsync(
            source, includeResolved, q, page, size, ct);

        var vm = new LoadExceptionsViewModel
        {
            Rows = rows, TotalRows = total, BySource = bySource,
            SourceKey = source, IncludeResolved = includeResolved, Search = q,
            PageNo = page, PageSize = size ?? 50, CanWrite = CanWrite
        };

        return IsAjax ? PartialView("_ExceptionsTable", vm) : View(vm);
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Resolve(long loadExceptionId, CancellationToken ct = default)
        => WriteAsync(
            () => _roster.ResolveExceptionAsync(loadExceptionId, ct),
            "Marked as dealt with.",
            () => RedirectToAction(nameof(Index)));

    /// <summary>The answer to a personnel-number mismatch. Never a fuzzy match on a name.</summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> MapAlias(
        string sourceKey, string aliasKey, string personnelNo, string? note, CancellationToken ct = default)
        => WriteAsync(
            () => _roster.SaveAliasAsync(sourceKey, aliasKey, personnelNo, note, ct),
            $"{aliasKey} now maps to {personnelNo}. Re-run the sync to pick up its rows.",
            () => RedirectToAction(nameof(Index)));

    /* ---- the loads themselves --------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> LoadRoster(CancellationToken ct = default)
        => WriteAsync(
            () => _roster.LoadRosterAsync(ct),
            "The roster was loaded and the organisation tree rebuilt.",
            () => RedirectToAction(nameof(Index)));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SyncEvidence(CancellationToken ct = default)
        => WriteAsync(
            () => _roster.SyncEvidenceAsync(ct),
            "Every mapped source was synced and the metrics rebuilt.",
            () => RedirectToAction(nameof(Index)));
}

/// <summary>
/// The startup self-check, on demand. Fail loudly here rather than on the screen that
/// needs the row.
/// </summary>
[Area("Admin")]
public sealed class HealthController : MaseeraController
{
    public const string Screen = "/Admin/Health/";

    private readonly SelfCheck _selfCheck;
    private readonly AuditRepository _audit;

    public HealthController(SelfCheck selfCheck, AuditRepository audit)
    {
        _selfCheck = selfCheck;
        _audit = audit;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(CancellationToken ct = default)
    {
        var report = await _selfCheck.RunAsync(throwOnFatal: false, ct);
        var changes = await _audit.ChangesAsync(pageSize: 25, ct: ct);

        return View(new HealthViewModel { Report = report, RecentChanges = changes });
    }

    /// <summary>
    /// The endpoint the load balancer watches. It is deliberately terse: a status code
    /// and a word, with nothing about the database's shape in it.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Live(CancellationToken ct = default)
    {
        var report = await _selfCheck.RunAsync(throwOnFatal: false, ct);
        Response.StatusCode = report.HasFatal
            ? StatusCodes.Status503ServiceUnavailable
            : StatusCodes.Status200OK;
        return Content(report.HasFatal ? "unhealthy" : "healthy", "text/plain");
    }
}
