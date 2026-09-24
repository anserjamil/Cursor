using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/// <summary>
/// Succession identify: the HIPO pool plus Non HIPO pulls, department plans, a level
/// census, and the by-position view.
/// </summary>
[Area("Selection")]
public sealed class SuccessionIdentifyController : StageControllerBase
{
    public const string Screen = "/Selection/SuccessionIdentify/";

    public SuccessionIdentifyController(StageRepository stages, RosterRepository roster)
        : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public Task<IActionResult> Index(
        int cycleStageId, string? pill = null, string? q = null, string? columns = null,
        string? filters = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
        => RenderStageAsync(cycleStageId, pill, q, columns, filters, sort, dir, page, size, ct);

    /// <summary>The department plans, with the level census beside them.</summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Plans(
        int cycleStageId, string? q = null, string? department = null, CancellationToken ct = default)
    {
        var (state, tabs) = await Stages.StateAsync(cycleStageId, ct);
        if (state is null) return Refusal("That stage no longer exists.", "Nothing to show");

        var plans = await Stages.PlansAsync(cycleStageId, q, department, ct);

        return View(new SuccessionViewModel
        {
            State = state, Tabs = tabs, Plans = plans,
            CanWrite = CanWrite && state.CanWrite, Search = q, Department = department
        });
    }

    /// <summary>
    /// Positions with incumbents for the incumbent suffix, and the successors named
    /// against each. When no position table is mapped it says so, rather than showing
    /// an empty list.
    /// </summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> ByPosition(int cycleStageId, string? q = null, CancellationToken ct = default)
    {
        var (state, tabs) = await Stages.StateAsync(cycleStageId, ct);
        if (state is null) return Refusal("That stage no longer exists.", "Nothing to show");

        var positions = await Stages.ByPositionAsync(cycleStageId, q, ct);
        if (positions.Problem is not null && positions.Positions.Count == 0)
            return Refusal(positions.Problem, "No positions to show");

        return View(new ByPositionViewModel
        {
            State = state, Tabs = tabs, Positions = positions,
            CanWrite = CanWrite && state.CanWrite, Search = q
        });
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SavePlan(
        int cycleStageId, string personnelNo, string department, string? levelCode,
        short? planYear, string? remark, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.SavePlanAsync(cycleStageId, personnelNo, department, levelCode, planYear, remark, ct),
            $"Planned in {department}.",
            () => RedirectToAction(nameof(Plans), new { cycleStageId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> BulkAddPlan(
        int cycleStageId, string[] personnelNo, string department, string? levelCode,
        CancellationToken ct = default)
        => WriteAsync(
            () => Stages.BulkAddPlanAsync(cycleStageId, personnelNo, department, levelCode, ct),
            $"{personnelNo.Length} people were planned in {department}.",
            () => RedirectToAction(nameof(Plans), new { cycleStageId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DropPlan(
        int cycleStageId, long planRowId, string? reason, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.DropPlanAsync(planRowId, reason, ct),
            "Dropped from the plan. The plan itself is kept as history.",
            () => RedirectToAction(nameof(Plans), new { cycleStageId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveSlot(
        int cycleStageId, string positionCode, string successorPersonnelNo,
        string? incumbentPersonnelNo, string? levelCode, string? remark, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.SaveSlotAsync(cycleStageId, positionCode, successorPersonnelNo,
                incumbentPersonnelNo, levelCode, remark, ct),
            "The successor was named.",
            () => RedirectToAction(nameof(ByPosition), new { cycleStageId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemoveSlot(int cycleStageId, long slotId, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.RemoveSlotAsync(slotId, ct),
            "The successor was removed from that position.",
            () => RedirectToAction(nameof(ByPosition), new { cycleStageId }));
}

/// <summary>
/// Succession review: readiness per plan with a remark, level history across years, and
/// the plan check that shows where the days were actually served.
/// </summary>
[Area("Selection")]
public sealed class SuccessionReviewController : StageControllerBase
{
    public const string Screen = "/Selection/SuccessionReview/";

    public SuccessionReviewController(StageRepository stages, RosterRepository roster)
        : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        int cycleStageId, string? q = null, string? department = null, CancellationToken ct = default)
    {
        var (state, tabs) = await Stages.StateAsync(cycleStageId, ct);
        if (state is null) return Refusal("That stage no longer exists.", "Nothing to show");

        var plans = await Stages.PlansAsync(cycleStageId, q, department, ct);

        return View(new SuccessionViewModel
        {
            State = state, Tabs = tabs, Plans = plans,
            CanWrite = CanWrite && state.CanWrite, Search = q, Department = department
        });
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveReadiness(
        int cycleStageId, long planRowId, string levelCode, string? remark, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.SaveReadinessAsync(cycleStageId, planRowId, levelCode, remark, ct),
            $"Readiness set to {levelCode}.",
            () => RedirectToAction(nameof(Index), new { cycleStageId }));

    /// <summary>
    /// The framework requirement met, against the plan-specific rule. The two can
    /// legitimately differ, and the panel shows both.
    /// </summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> PlanCheck(long planRowId, CancellationToken ct = default)
    {
        var check = await Stages.PlanCheckAsync(planRowId, ct);
        if (check.Problem is not null) return PartialView("_Refusal", check.Problem);
        return PartialView("_PlanCheck", check);
    }
}

/// <summary>Succession calibration reuses the stage screen unchanged.</summary>
[Area("Selection")]
public sealed class SuccessionCalibrateController : StageControllerBase
{
    public const string Screen = "/Selection/SuccessionCalibrate/";

    public SuccessionCalibrateController(StageRepository stages, RosterRepository roster)
        : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public Task<IActionResult> Index(
        int cycleStageId, string? pill = null, string? q = null, string? columns = null,
        string? filters = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
        => RenderStageAsync(cycleStageId, pill, q, columns, filters, sort, dir, page, size, ct);
}
