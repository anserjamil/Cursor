using Maseera.Core.Dtos;
using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/// <summary>
/// Identify, Review and Calibration are one screen with three sets of pills, and
/// succession and development reuse the same shape.
///
/// One procedure serves all of them, so the three cannot drift apart: the funnel, the
/// rows and the true total come back from sel.usp_Stage_Candidates in a single call, and
/// which box a person is in is decided by sel.fn_CandidateBox rather than by anything
/// here.
/// </summary>
public abstract class StageControllerBase : MaseeraController
{
    protected readonly StageRepository Stages;
    protected readonly RosterRepository Roster;

    protected StageControllerBase(StageRepository stages, RosterRepository roster)
    {
        Stages = stages;
        Roster = roster;
    }

    /// <summary>The view each concrete stage renders. They differ only in their pills.</summary>
    protected abstract string StageViewName { get; }

    protected async Task<IActionResult> RenderStageAsync(
        int cycleStageId, string? pill, string? q, string? columns, string? filters,
        string? sort, string? dir, int page, int? size, CancellationToken ct)
    {
        var (state, tabs) = await Stages.StateAsync(cycleStageId, ct);
        if (state is null)
            return Refusal("That stage no longer exists.", "Nothing to show");

        // The column set is the viewer's saved view unless they asked for another.
        var (catalogue, views) = await Roster.ColumnCatalogAsync(ScreenCode, ct: ct);
        var saved = views.FirstOrDefault(v => v.LoginName == User_.LoginName)
                    ?? views.FirstOrDefault(v => v.IsPreset);
        var columnSet = columns ?? saved?.ColumnList;

        var page1 = await Stages.CandidatesAsync(
            cycleStageId, pill, q, columnSet, filters, sort, dir, page, size, ct);

        var vm = new StageViewModel
        {
            State = state,
            Tabs = tabs,
            Page = page1,
            Columns = catalogue,
            SavedViews = views,
            ActiveColumns = (columnSet ?? string.Empty)
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries),
            ActivePill = pill,
            Search = q,
            SortBy = sort,
            SortDir = dir,
            PageNo = page,
            FilterJson = filters,
            CanWrite = CanWrite && state.CanWrite,
            TestModeNote = User_.TestMode ? await Config.MessageAsync("TEST_MODE_ON", ct) : null
        };

        // The table, the funnel and the pager refresh on their own; the chrome does not.
        return IsAjax ? PartialView("_StageTable", vm) : View(StageViewName, vm);
    }

    /* ---- decisions -------------------------------------------------------------- */

    [HttpPost]
    public Task<IActionResult> Decide(
        int cycleStageId, string[] personnelNo, string decisionCode, string? reason,
        CancellationToken ct = default)
        => WriteAsync(
            () => Stages.SaveDecisionAsync(cycleStageId, personnelNo, decisionCode, reason, ct: ct),
            DecisionToast(personnelNo.Length, decisionCode),
            () => RedirectToAction("Index", new { cycleStageId }));

    [HttpPost]
    public Task<IActionResult> ClearDecision(
        int cycleStageId, string[] personnelNo, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.ClearDecisionAsync(cycleStageId, personnelNo, ct: ct),
            personnelNo.Length == 1
                ? "The decision was cleared, and the clearing is in the log."
                : $"{personnelNo.Length} decisions were cleared, and each clearing is in the log.",
            () => RedirectToAction("Index", new { cycleStageId }));

    private static string DecisionToast(int count, string decisionCode)
    {
        var what = decisionCode switch
        {
            "NOMINATED" => "nominated",
            "WATCH" => "moved to the watch list",
            "DROPPED" => "dropped",
            "NONHIPO" => "pulled in as non-HIPO",
            _ => "decided"
        };

        return count == 1 ? $"One person was {what}." : $"{count} people were {what}.";
    }

    /* ---- add people ------------------------------------------------------------- */

    [HttpGet]
    public async Task<IActionResult> SearchPeople(
        int cycleStageId, string? q, CancellationToken ct = default)
        => PartialView("_AddPeople", await Stages.SearchPeopleAsync(cycleStageId, q, ct: ct));

    [HttpPost]
    public Task<IActionResult> AddPeople(
        int cycleStageId, string[] personnelNo, CancellationToken ct = default)
        => WriteAsync(
            () => Stages.AddPeopleAsync(cycleStageId, personnelNo, ct),
            personnelNo.Length == 1
                ? "One person was added, flagged with where they came from."
                : $"{personnelNo.Length} people were added, each flagged with where they came from.",
            () => RedirectToAction("Index", new { cycleStageId }));

    /* ---- panels ----------------------------------------------------------------- */

    /// <summary>Advisory only. Nothing here is recorded until somebody decides it.</summary>
    [HttpGet]
    public async Task<IActionResult> Suggestions(int cycleStageId, CancellationToken ct = default)
        => PartialView("_Suggestions", await Stages.SuggestionsAsync(cycleStageId, ct: ct));

    /// <summary>A column filter's values, with counts, from a procedure.</summary>
    [HttpGet]
    public async Task<IActionResult> ColumnValues(
        int cycleStageId, string columnName, string? q, CancellationToken ct = default)
    {
        var result = await Stages.ColumnValuesAsync(cycleStageId, columnName, q, ct);
        return Json(new
        {
            ok = result.Ok,
            problem = result.Problem,
            values = result.Rows.Select(r => new { value = r.Value, count = r.Cnt })
        });
    }

    [HttpGet]
    public async Task<IActionResult> Focus(
        int cycleStageId, string personnelNo, CancellationToken ct = default)
    {
        var (state, _) = await Stages.StateAsync(cycleStageId, ct);
        var profile = await Stages.ProfileAsync(personnelNo, state?.CycleId, ct);

        if (profile.Problem is not null)
            return PartialView("_Refusal", profile.Problem);

        return PartialView("_FocusPane", new FocusPaneViewModel
        {
            Profile = profile,
            CycleStageId = cycleStageId,
            CycleId = state?.CycleId,
            CanWrite = CanWrite && (state?.CanWrite ?? false)
        });
    }
}
