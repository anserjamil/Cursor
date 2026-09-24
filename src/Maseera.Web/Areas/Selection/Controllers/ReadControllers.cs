using Maseera.Data;
using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/// <summary>
/// The development stages: propose an activity per person, or mark it not required, then
/// approve into the plan or return to identify. The table and the funnel are the stage
/// screen's, unchanged.
/// </summary>
[Area("Selection")]
public sealed class DevelopController : StageControllerBase
{
    public const string Screen = "/Selection/Develop/";

    public DevelopController(StageRepository stages, RosterRepository roster) : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public Task<IActionResult> Index(
        int cycleStageId, string? pill = null, string? q = null, string? columns = null,
        string? filters = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
        => RenderStageAsync(cycleStageId, pill, q, columns, filters, sort, dir, page, size, ct);
}

/// <summary>Up to six candidates side by side, each removable and openable.</summary>
[Area("Selection")]
public sealed class CompareController : MaseeraController
{
    public const string Screen = "/Selection/Compare/";

    private readonly StageRepository _stages;
    private readonly IConfigCache _config;

    public CompareController(StageRepository stages, IConfigCache config)
    {
        _stages = stages;
        _config = config;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        string[]? personnelNo, int? cycleId = null, CancellationToken ct = default)
    {
        personnelNo ??= [];
        var max = (int)await _config.NumberAsync(SettingKeys.CompareMax, 6, ct);

        if (personnelNo.Length == 0)
            return View(new CompareViewModel { Max = max });

        var result = await _stages.CompareAsync(personnelNo, cycleId, ct);

        return View(new CompareViewModel
        {
            People = result.Rows,
            Problem = result.Problem,
            Max = max,
            CycleId = cycleId
        });
    }
}

/// <summary>
/// The employee roster: a server-paged read of the mapped table. Sensitive columns are
/// readable on a record and refused as filters, and the refusal says why.
/// </summary>
[Area("Selection")]
public sealed class EmployeesController : MaseeraController
{
    public const string Screen = "/Selection/Employees/";

    private readonly RosterRepository _roster;

    public EmployeesController(RosterRepository roster) => _roster = roster;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        string? q = null, string? org = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
    {
        var (rows, total, problem) = await _roster.RosterAsync(q, org, sort, dir, page, size, ct);

        if (problem is not null && rows.Count == 0)
            return Refusal(problem, "The roster could not be read");

        var vm = new RosterViewModel
        {
            Rows = rows, TotalRows = total, Problem = problem,
            Search = q, OrgCode = org, SortBy = sort, SortDir = dir,
            PageNo = page, PageSize = size ?? 50
        };

        return IsAjax ? PartialView("_RosterTable", vm) : View(vm);
    }
}

/// <summary>
/// The profile, and the readiness ladder that is the reason this screen exists: each
/// level lists what it asks, what was met, and how far along the person is — with the
/// reason on every requirement.
/// </summary>
[Area("Selection")]
public sealed class ProfileController : MaseeraController
{
    public const string Screen = "/Selection/Employees/";

    private readonly StageRepository _stages;
    private readonly PoolRepository _pool;

    public ProfileController(StageRepository stages, PoolRepository pool)
    {
        _stages = stages;
        _pool = pool;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        string personnelNo, int? cycleId = null, CancellationToken ct = default)
    {
        var profile = await _stages.ProfileAsync(personnelNo, cycleId, ct);

        if (profile.Problem is not null)
            return Refusal(profile.Problem, "This person cannot be shown");

        if (profile.Person is null)
            return Refusal("There is nobody with that personnel number.", "Nothing to show");

        return View(new ProfileViewModel { Profile = profile, CycleId = cycleId });
    }

    /// <summary>
    /// The auditor's trace: each criterion and the value that satisfied it. Readable
    /// without being able to change anything.
    /// </summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Trace(int cycleId, string personnelNo, CancellationToken ct = default)
    {
        var trace = await _pool.TraceAsync(cycleId, personnelNo, ct);
        if (trace.Problem is not null) return PartialView("_Refusal", trace.Problem);
        return PartialView("_Trace", trace);
    }
}

/// <summary>Read models over the same procedures the screens read.</summary>
[Area("Selection")]
public sealed class ReportsController : MaseeraController
{
    public const string Screen = "/Selection/Cycles/";

    private readonly ReportRepository _reports;
    private readonly CycleRepository _cycles;

    public ReportsController(ReportRepository reports, CycleRepository cycles)
    {
        _reports = reports;
        _cycles = cycles;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(string? key = null, int? cycleId = null, CancellationToken ct = default)
    {
        var definitions = await _reports.ListAsync(ct);
        var (cycles, _) = await _cycles.ListAsync(ct: ct);

        var vm = new ReportsViewModel
        {
            Definitions = definitions,
            Cycles = cycles,
            ActiveKey = key,
            CycleId = cycleId
        };

        if (key is not null)
            vm = vm with { Result = await _reports.RunAsync(key, cycleId, ct) };

        return IsAjax ? PartialView("_ReportTable", vm) : View(vm);
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Download(
        string key, int? cycleId = null, string format = "csv", CancellationToken ct = default)
    {
        var result = await _reports.RunAsync(key, cycleId, ct);

        if (result.Problem is not null)
        {
            ToastWarn(result.Problem);
            return RedirectToAction(nameof(Index), new { key, cycleId });
        }

        var name = $"maseera-{key.ToLowerInvariant()}-{User_.AsOf:yyyy-MM-dd}";
        return format.Equals("xlsx", StringComparison.OrdinalIgnoreCase)
            ? Downloads.Xlsx(result.Rows, name, key)
            : Downloads.Csv(result.Rows, name);
    }
}

/// <summary>
/// The decision log: every user decision as a row, filterable by word, reachable from
/// any stage.
/// </summary>
[Area("Selection")]
public sealed class AuditController : MaseeraController
{
    public const string Screen = "/Selection/Cycles/";

    private readonly StageRepository _stages;
    private readonly CycleRepository _cycles;

    public AuditController(StageRepository stages, CycleRepository cycles)
    {
        _stages = stages;
        _cycles = cycles;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        int? cycleId = null, int? cycleStageId = null, string? personnelNo = null,
        string? decision = null, string? q = null, bool? testOnly = null,
        int page = 1, int? size = null, CancellationToken ct = default)
    {
        var log = await _stages.DecisionLogAsync(cycleId, cycleStageId, personnelNo,
            decision, q, testOnly, page, size, ct);
        var (cycles, _) = await _cycles.ListAsync(ct: ct);

        var vm = new DecisionLogViewModel
        {
            Log = log, Cycles = cycles, CycleId = cycleId, ActiveDecision = decision,
            Search = q, TestOnly = testOnly, PageNo = page, PageSize = size ?? 50
        };

        return IsAjax ? PartialView("_LogTable", vm) : View(vm);
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Download(
        int? cycleId = null, string? decision = null, string? q = null,
        string format = "csv", CancellationToken ct = default)
    {
        // Paging off: the export is the whole log, not the page that happened to be shown.
        var log = await _stages.DecisionLogAsync(cycleId, null, null, decision, q, null,
            pageNo: 1, pageSize: int.MaxValue, ct);

        var rows = log.Rows.Select(r => (IDictionary<string, object?>)new Dictionary<string, object?>
        {
            ["Decided on"] = r.DecidedOnUtc,
            ["Personnel No"] = r.PersonnelNo,
            ["Name"] = r.FullName,
            ["Organisation"] = r.OrgName,
            ["Cycle"] = r.CycleName,
            ["Process"] = r.ProcessName,
            ["Stage"] = r.StageName,
            ["Decision"] = r.DecisionName,
            ["Reason"] = r.Reason,
            ["Decided by"] = r.PerformerName,
            ["Actor"] = r.ActorName ?? r.ActorLogin,
            ["Test"] = r.IsTest
        }).ToList();

        var name = $"maseera-decision-log-{User_.AsOf:yyyy-MM-dd}";
        return format.Equals("xlsx", StringComparison.OrdinalIgnoreCase)
            ? Downloads.Xlsx(rows, name, "Decision log")
            : Downloads.Csv(rows, name);
    }
}
