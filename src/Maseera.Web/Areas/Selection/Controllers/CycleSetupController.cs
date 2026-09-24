using Maseera.Core.Dtos;
using Maseera.Data;
using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/// <summary>
/// The cycle design list, the "What kind of cycle is this?" chooser, and the wizard.
///
/// The steps come from sel.WizardStep — six are seeded and nothing here assumes six.
/// </summary>
[Area("Selection")]
public sealed class CycleSetupController : MaseeraController
{
    public const string Screen = "/Selection/CycleSetup/";

    private readonly CycleRepository _cycles;
    private readonly PoolRepository _pool;
    private readonly FrameworkRepository _frameworks;
    private readonly RosterRepository _roster;
    private readonly ConfigRepository _config;

    public CycleSetupController(
        CycleRepository cycles, PoolRepository pool, FrameworkRepository frameworks,
        RosterRepository roster, ConfigRepository config)
    {
        _cycles = cycles;
        _pool = pool;
        _frameworks = frameworks;
        _roster = roster;
        _config = config;
    }

    /// <summary>
    /// Every design, with "configured" shown as five tracks rather than a percentage —
    /// so you can see which step is missing without reading a number.
    /// </summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(string? q, CancellationToken ct = default)
    {
        var (cycles, tracks) = await _cycles.ListAsync(search: q, ct: ct);

        return View(new CycleSetupListViewModel
        {
            Cycles = cycles,
            TracksByCycle = tracks.GroupBy(t => t.CycleId)
                .ToDictionary(g => g.Key, g => (IReadOnlyList<CycleTrackRow>)g.OrderBy(t => t.SortOrder).ToList()),
            CanWrite = CanWrite,
            Search = q
        });
    }

    /// <summary>New design never opens an empty form: it asks what kind of cycle this is.</summary>
    [HttpGet]
    [ScreenAccess(Screen, Write = true)]
    public async Task<IActionResult> New(string? recipe, CancellationToken ct = default)
    {
        var (recipes, copyable) = await _cycles.RecipesAsync(ct);

        IReadOnlyList<JobSuffixRow> suffixes = [];
        string? suffixProblem = null;

        // The second step of a Talent Cycle asks which job suffixes it covers, and the
        // dropdowns read the roster through a procedure.
        if (recipes.Any(r => r.RecipeCode == recipe && r.AsksJobSuffix))
        {
            var result = await _cycles.JobSuffixesAsync(chiefOnly: true, ct);
            suffixes = result.Rows;
            suffixProblem = result.Problem;
        }

        return View(new NewDesignViewModel
        {
            Recipes = recipes,
            Copyable = copyable,
            JobSuffixes = suffixes,
            JobSuffixProblem = suffixProblem,
            ChosenRecipe = recipe
        });
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Create(
        string cycleCode, string name, int? recipeId,
        string? incumbentSuffix, string? successorSuffix, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveAsync(null, cycleCode, name, null, null, null, null, null,
                incumbentSuffix, successorSuffix, null, true, recipeId, ct),
            $"{name} was created as a draft.",
            () => RedirectToAction(nameof(Index)));

    /// <summary>One step of the wizard. Which step, and whether it is skippable, is data.</summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Step(int cycleId, int step = 1, CancellationToken ct = default)
    {
        var detail = await _cycles.DetailAsync(cycleId, ct);
        if (detail.Cycle is null)
            return Refusal("That cycle no longer exists.", "Nothing to design");

        var (todos, summary, _) = await _cycles.ValidateAsync(cycleId, ct);

        // Each step loads only what it needs: the wizard is six screens, not one big one.
        // The two engine reads are done once and held, because each one walks the pool.
        var attainment = step == 3 ? await _frameworks.AttainmentAsync(cycleId, ct: ct) : default;
        var spread = step == 4 ? await _frameworks.ReadinessSpreadAsync(cycleId, ct) : default;

        var vm = new WizardViewModel
        {
            Detail = detail,
            StepNo = step,
            Todos = todos,
            Summary = summary,
            CanWrite = CanWrite && detail.Cycle.CanEdit,
            ReadOnlyReason = detail.Cycle.EditRefusal,

            Pool = step == 2 ? await _pool.PreviewAsync(cycleId, ct: ct) : null,
            Fields = step == 2 ? (await _roster.FieldsAsync(enabledOnly: true, ct: ct)).Fields : [],
            Operators = step == 2 ? await _config.OperatorsAsync(ct: ct) : [],
            SetModes = step == 2 ? await _config.DomainValuesAsync("SET_MODE", ct) : [],
            SetJoins = step == 2 ? await _config.DomainValuesAsync("CRITERIA_JOIN", ct) : [],

            Library = step == 3 ? await _frameworks.ListAsync(activeOnly: true, ct: ct) : [],
            Attainment = attainment.Items ?? [],
            AttainmentSummary = attainment.Summary,

            Spread = spread.Levels ?? [],
            SpreadSummary = spread.Summary,

            ManagementLevels = step == 5 ? await _config.DomainValuesAsync("MANAGEMENT_LEVEL", ct) : [],
            Performers = step == 5 ? (await _cycles.PerformersAsync(ct)).InUse : [],
            ProcessTypes = step == 5 ? await ProcessTypesAsync(ct) : []
        };

        return View("Step" + step, vm);
    }

    /// <summary>The live reach and sample behind the criteria builder.</summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> PoolPreview(
        int cycleId, int page = 1, string? q = null, CancellationToken ct = default)
    {
        var preview = await _pool.PreviewAsync(cycleId, page, null, q, ct);
        return PartialView("_PoolDrawer", preview);
    }

    private Task<IReadOnlyList<ProcessTypeOption>> ProcessTypesAsync(CancellationToken ct)
        => HttpContext.RequestServices.GetRequiredService<IProcRunner>()
            .ListAsync<ProcessTypeOption>("sel.usp_ProcessType_List", ct: ct);

    /* ---- writes ----------------------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveCycle(
        int cycleId, string cycleCode, string name, DateOnly? startDate, DateOnly? endDate,
        string? ownerLogin, string? delegateLogin, string? notes, string? incumbentSuffix,
        string? successorSuffix, string? existingPoolCode, bool activeMembersOnly = true,
        CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveAsync(cycleId, cycleCode, name, startDate, endDate, ownerLogin,
                delegateLogin, notes, incumbentSuffix, successorSuffix, existingPoolCode,
                activeMembersOnly, null, ct),
            "The cycle was saved.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 1 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SkipStep(int cycleId, int stepNo, bool isSkipped, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SetStepSkippedAsync(cycleId, stepNo, isSkipped, ct),
            isSkipped ? "That step was marked as skipped." : "That step is back in the design.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = stepNo }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveCriterionSet(
        int cycleId, int? criterionSetId, string setModeCode, string? setJoinCode,
        CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveCriterionSetAsync(cycleId, criterionSetId, null, setModeCode, setJoinCode, ct),
            "The set was saved.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 2 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteCriterionSet(int cycleId, int criterionSetId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.DeleteCriterionSetAsync(criterionSetId, ct),
            "The set was removed.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 2 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveCriterion(
        int cycleId, int criterionSetId, int? criterionId, int rosterFieldId,
        string operatorCode, string? value1, string? value2, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveCriterionAsync(criterionSetId, criterionId, rosterFieldId,
                operatorCode, value1, value2, ct),
            "The criterion was saved.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 2 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteCriterion(int cycleId, int criterionId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.DeleteCriterionAsync(criterionId, ct),
            "The criterion was removed.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 2 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> AssignFramework(int cycleId, int devFrameworkId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.AssignFrameworkAsync(cycleId, devFrameworkId, ct),
            "The framework was assigned.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 3 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemoveFramework(int cycleId, int devFrameworkId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.RemoveFrameworkAsync(cycleId, devFrameworkId, ct),
            "The framework was removed.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 3 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveLevel(
        int cycleId, int? cycleReadinessId, string levelCode, string name,
        decimal? thresholdPct, int? sortOrder, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveReadinessAsync(cycleId, cycleReadinessId, levelCode, name,
                thresholdPct, sortOrder, ct),
            "The level was saved.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 4 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteLevel(int cycleId, int cycleReadinessId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.DeleteReadinessAsync(cycleReadinessId, ct),
            "The level was removed.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 4 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveProcess(
        int cycleId, int? cycleProcessId, string processTypeCode, string? name,
        DateOnly? startDate, DateOnly? endDate, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveProcessAsync(cycleId, cycleProcessId, processTypeCode, name,
                startDate, endDate, ct),
            "The process was saved.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 5 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemoveProcess(int cycleId, int cycleProcessId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.RemoveProcessAsync(cycleProcessId, ct),
            "The process was removed.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 5 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveStage(
        int cycleId, int cycleProcessId, int? cycleStageId, string? name,
        DateOnly? startDate, DateOnly? endDate, string? performerCode, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.SaveStageAsync(cycleProcessId, cycleStageId, null, name, startDate,
                endDate, performerCode, null, ct),
            "The stage was saved.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 5 }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> AddPerformer(int cycleId, string levelCode, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.AddPerformerAsync(levelCode, ct),
            "That title can now perform a stage.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 5 }));

    /// <summary>Removing a title clears it from every design, and the toast says how many.</summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemovePerformer(int cycleId, string levelCode, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.RemovePerformerAsync(levelCode, ct),
            "That title was removed, and cleared from every design that used it.",
            () => RedirectToAction(nameof(Step), new { cycleId, step = 5 }));

    /// <summary>
    /// Open resolves the pool, writes it as a snapshot, starts the first stage, and makes
    /// the draft Active permanently.
    /// </summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Open(int cycleId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.OpenAsync(cycleId, ct),
            "The cycle is open, and its pool has been written as a snapshot.",
            () => RedirectToAction("Index", "Cycles"));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Copy(int cycleId, string newCode, string newName, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.CopyAsync(cycleId, newCode, newName, ct),
            $"{newName} was created as a draft from that design.",
            () => RedirectToAction(nameof(Index)));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Delete(int cycleId, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.DeleteAsync(cycleId, ct),
            "The draft was deleted.",
            () => RedirectToAction(nameof(Index)));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Cancel(int cycleId, string? reason, CancellationToken ct = default)
        => WriteAsync(
            () => _cycles.CancelAsync(cycleId, reason, ct),
            "The cycle was cancelled. Its decisions are kept.",
            () => RedirectToAction("Index", "Cycles"));
}
