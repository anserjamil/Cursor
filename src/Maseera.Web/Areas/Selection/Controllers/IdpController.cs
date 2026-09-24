using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/// <summary>
/// The individual development plan: where a planner turns unmet requirements into booked,
/// dated, approved plans.
///
/// Four tabs, all server-rendered with AJAX partials. The rules the prototype fixes are
/// held by the procedures, not here — plan-level approval, never auto-assigned coverage,
/// seats respected, and a person who finishes staying on screen rather than re-sorting
/// away under the cursor.
/// </summary>
[Area("Selection")]
public sealed class IdpController : MaseeraController
{
    public const string Screen = "/Selection/Develop/";

    private readonly IdpRepository _idp;
    private readonly StageRepository _stages;

    public IdpController(IdpRepository idp, StageRepository stages)
    {
        _idp = idp;
        _stages = stages;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        int cycleStageId, string tab = "overview", string? personnelNo = null,
        int? devEventId = null, string? q = null, int page = 1, CancellationToken ct = default)
    {
        var (state, tabs) = await _stages.StateAsync(cycleStageId, ct);
        if (state is null) return Refusal("That stage no longer exists.", "Nothing to plan");

        var vm = new IdpViewModel
        {
            State = state,
            Tabs = tabs,
            ActiveTab = tab,
            CanWrite = CanWrite && state.CanWrite,
            Search = q,
            PersonnelNo = personnelNo,
            DevEventId = devEventId
        };

        switch (tab)
        {
            case "person" when personnelNo is not null:
                vm = vm with { Person = await _idp.PersonAsync(cycleStageId, personnelNo, ct) };
                vm = vm with { Conflicts = await _idp.ConflictsAsync(cycleStageId, personnelNo, ct) };
                break;

            case "booking":
                var (rows, total) = await _idp.RequirementsAsync(
                    cycleStageId, devEventId, q, openOnly: true, pageNo: page, ct: ct);
                vm = vm with
                {
                    Requirements = rows,
                    RequirementTotal = total,
                    Sessions = await _idp.SessionsAsync(devEventId, ct: ct),
                    Board = await _idp.BoardAsync(cycleStageId, ct)
                };
                break;

            case "coverage":
                var (assignments, successors) = await _idp.CoverageBoardAsync(cycleStageId, q, ct);
                vm = vm with
                {
                    CoverageAssignments = assignments,
                    Successors = successors,
                    Conflicts = await _idp.ConflictsAsync(cycleStageId, ct: ct)
                };
                break;

            default:
                vm = vm with
                {
                    Board = await _idp.BoardAsync(cycleStageId, ct),
                    Risk = await _idp.RiskAsync(cycleStageId, ct)
                };
                break;
        }

        return IsAjax ? PartialView("_Tab" + char.ToUpperInvariant(tab[0]) + tab[1..], vm) : View(vm);
    }

    /* ---- booking ---------------------------------------------------------------- */

    /// <summary>
    /// Seats are respected by the procedure, and an over-booking comes back as a sentence
    /// naming how many places are left.
    /// </summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Book(
        int cycleStageId, int devSessionId, string[] personnelNo, string tab = "booking",
        CancellationToken ct = default)
        => WriteAsync(
            () => _idp.BookAsync(cycleStageId, devSessionId, personnelNo, ct),
            personnelNo.Length == 1 ? "Booked." : $"{personnelNo.Length} people were booked.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Pencil(
        int cycleStageId, int devEventId, DateOnly pencilledDate, string[] personnelNo,
        string tab = "booking", CancellationToken ct = default)
        => WriteAsync(
            () => _idp.PencilAsync(cycleStageId, devEventId, pencilledDate, personnelNo, ct),
            "Pencilled in. No session is scheduled for it yet.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab }));

    /// <summary>
    /// One-click Suggest. It returns what it did as sentences, so the planner can see
    /// exactly what was booked and what was left for them.
    /// </summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public async Task<IActionResult> Suggest(
        int cycleStageId, string? personnelNo = null, CancellationToken ct = default)
    {
        var result = await _idp.SuggestAsync(cycleStageId, personnelNo, ct);

        if (result.Problem is not null) ToastWarn(result.Problem);
        else if (result.Changed == 0) ToastOk("There was nothing left to plan.");
        else ToastOk($"{result.Changed} requirement{(result.Changed == 1 ? " was" : "s were")} planned.");

        if (IsAjax)
        {
            return Json(new
            {
                ok = result.Problem is null,
                problem = result.Problem,
                changed = result.Changed,
                sentences = result.Sentences.OrderBy(s => s.SortOrder).Select(s => s.Sentence)
            });
        }

        return RedirectToAction(nameof(Index),
            new { cycleStageId, tab = personnelNo is null ? "overview" : "person", personnelNo });
    }

    /* ---- coverage --------------------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> AddCoverage(
        int cycleStageId, string personnelNo, int? devEventId, string? department,
        string? positionCode, string? incumbentPersonnelNo, DateOnly startDate, DateOnly endDate,
        string tab = "coverage", CancellationToken ct = default)
        => WriteAsync(
            () => _idp.AddCoverageAsync(cycleStageId, personnelNo, devEventId, department,
                positionCode, incumbentPersonnelNo, startDate, endDate, ct),
            "The coverage was assigned, and the days were deducted.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab, personnelNo }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemoveCoverage(
        int cycleStageId, long idpCoverageId, string tab = "coverage", CancellationToken ct = default)
        => WriteAsync(
            () => _idp.RemoveCoverageAsync(idpCoverageId, ct),
            "The coverage was removed, and the days were given back.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab }));

    /* ---- the plan --------------------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveTarget(
        int cycleStageId, string personnelNo, DateOnly? targetDate, CancellationToken ct = default)
        => WriteAsync(
            () => _idp.SaveTargetAsync(cycleStageId, personnelNo, targetDate, ct),
            targetDate is null
                ? "The target date is derived from the readiness level again."
                : "The target date was set.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab = "person", personnelNo }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> AddNote(
        int cycleStageId, string personnelNo, string noteText, CancellationToken ct = default)
        => WriteAsync(
            () => _idp.AddNoteAsync(cycleStageId, personnelNo, noteText, ct),
            "The note was added.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab = "person", personnelNo }));

    /// <summary>Approval is at plan level, never per requirement.</summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Approve(
        int cycleStageId, string[] personnelNo, string tab = "overview", CancellationToken ct = default)
        => WriteAsync(
            () => _idp.ApproveAsync(cycleStageId, personnelNo, ct),
            personnelNo.Length == 1
                ? "The plan was approved and the person was notified."
                : $"{personnelNo.Length} plans were approved and those people were notified.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab }));

    /* ---- sessions and export ---------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveSession(
        int cycleStageId, int? devSessionId, int devEventId, string sessionCode,
        DateOnly? startDate, DateOnly? endDate, int? seats, string? location,
        bool isCancelled = false, CancellationToken ct = default)
        => WriteAsync(
            () => _idp.SaveSessionAsync(devSessionId, devEventId, sessionCode, startDate,
                endDate, seats, location, isCancelled, ct),
            "The session was saved.",
            () => RedirectToAction(nameof(Index), new { cycleStageId, tab = "booking", devEventId }));

    /// <summary>
    /// Streams from the same procedure the screen reads, with paging off — never from
    /// what happens to be on screen.
    /// </summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Export(int cycleStageId, string format = "csv", CancellationToken ct = default)
    {
        var rows = await _idp.ExportAsync(cycleStageId, ct);
        var name = $"maseera-development-plans-{User_.AsOf:yyyy-MM-dd}";

        return format.Equals("xlsx", StringComparison.OrdinalIgnoreCase)
            ? Downloads.Xlsx(rows, name, "Development plans")
            : Downloads.Csv(rows, name);
    }
}
