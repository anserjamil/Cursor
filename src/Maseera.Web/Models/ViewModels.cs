using Maseera.Core.Dtos;
using Maseera.Data.Repositories;

namespace Maseera.Web.Models;

public sealed class CyclesIndexViewModel
{
    public IReadOnlyList<CycleRow> Cycles { get; init; } = [];
    public IReadOnlyDictionary<int, IReadOnlyList<CycleTrackRow>> TracksByCycle { get; init; }
        = new Dictionary<int, IReadOnlyList<CycleTrackRow>>();
    public IReadOnlyDictionary<int, IReadOnlyList<CycleSpineRow>> StagesByCycle { get; init; }
        = new Dictionary<int, IReadOnlyList<CycleSpineRow>>();
    public IReadOnlyDictionary<int, CycleWaitingRow> WaitingByCycle { get; init; }
        = new Dictionary<int, CycleWaitingRow>();

    public string? StatusFilter { get; init; }
    public string? Search { get; init; }
    public bool MineOnly { get; init; }
    public bool CanWrite { get; init; }
    public string EmptyMessage { get; init; } = string.Empty;

    /* The four stats in the hero band, all scoped to this viewer. */
    public int ActiveCount => Cycles.Count(c => c.StatusCode == "ACTIVE");
    public int DraftCount => Cycles.Count(c => c.StatusCode == "DRAFT");
    public int InPoolTotal => Cycles.Where(c => c.StatusCode == "ACTIVE").Sum(c => c.PoolCount);
    public int HighPotentialTotal => Cycles.Where(c => c.StatusCode == "ACTIVE").Sum(c => c.HighPotentialCount);

    /// <summary>
    /// The one primary action a cycle is waiting on. Which stage it is comes from the
    /// database; this only turns it into a caption.
    /// </summary>
    public (string Caption, string? RouteKey, int? StageId) PrimaryAction(CycleRow cycle)
    {
        if (cycle.StatusCode == "DRAFT")
            return ("Continue design", null, null);

        if (cycle.StatusCode is "CLOSED" or "CANCELLED")
            return ("Copy to new design", null, null);

        if (WaitingByCycle.TryGetValue(cycle.CycleId, out var waiting)
            && waiting.WaitingStageId is { } stageId
            && waiting.WaitingState == "OPEN")
        {
            return ($"Open {waiting.WaitingStageName?.ToLowerInvariant()}", waiting.WaitingRouteKey, stageId);
        }

        return ("Open cycle", null, null);
    }
}

public sealed class RefusalViewModel
{
    public int StatusCode { get; init; }
    public string? ScreenName { get; init; }
    public string Sentence { get; init; } = string.Empty;
    public bool IsRegistered { get; init; }
    public string LoginName { get; init; } = string.Empty;
}

public sealed class CycleSetupListViewModel
{
    public IReadOnlyList<CycleRow> Cycles { get; init; } = [];
    public IReadOnlyDictionary<int, IReadOnlyList<CycleTrackRow>> TracksByCycle { get; init; }
        = new Dictionary<int, IReadOnlyList<CycleTrackRow>>();
    public bool CanWrite { get; init; }
    public string? Search { get; init; }

    /// <summary>The five tracks, in order, with a caption each.</summary>
    public static readonly IReadOnlyList<(string Code, string Caption)> Tracks =
    [
        ("CYCLE", "The cycle"),
        ("POOL", "Eligible pool"),
        ("FRAMEWORK", "Framework"),
        ("READINESS", "Levels"),
        ("STAGES", "Stages"),
    ];
}

public sealed class NewDesignViewModel
{
    public IReadOnlyList<CycleRecipeRow> Recipes { get; init; } = [];
    public IReadOnlyList<CycleRow> Copyable { get; init; } = [];
    public IReadOnlyList<JobSuffixRow> JobSuffixes { get; init; } = [];
    public string? JobSuffixProblem { get; init; }
    public string? ChosenRecipe { get; init; }
}

public sealed class WizardViewModel
{
    public required CycleDetail Detail { get; init; }
    public int StepNo { get; init; }
    public required IReadOnlyList<ValidationTodoRow> Todos { get; init; }
    public required ValidationSummary Summary { get; init; }
    public bool CanWrite { get; init; }
    public string? ReadOnlyReason { get; init; }

    /* Step 2 */
    public PoolPreview? Pool { get; init; }
    public IReadOnlyList<RosterFieldRow> Fields { get; init; } = [];
    public IReadOnlyList<OperatorRow> Operators { get; init; } = [];
    public IReadOnlyList<DomainValueRow> SetModes { get; init; } = [];
    public IReadOnlyList<DomainValueRow> SetJoins { get; init; } = [];

    /* Step 3 */
    public IReadOnlyList<FrameworkRow> Library { get; init; } = [];
    public IReadOnlyList<AttainmentItemRow> Attainment { get; init; } = [];
    public AttainmentSummary? AttainmentSummary { get; init; }

    /* Step 4 */
    public IReadOnlyList<ReadinessSpreadRow> Spread { get; init; } = [];
    public ReadinessSpreadSummary? SpreadSummary { get; init; }

    /* Step 5 */
    public IReadOnlyList<DomainValueRow> ManagementLevels { get; init; } = [];
    public IReadOnlyList<StagePerformerRow> Performers { get; init; } = [];
    public IReadOnlyList<ProcessTypeOption> ProcessTypes { get; init; } = [];

    /// <summary>
    /// "3 of 5 set · 1 skipped · still to do: Eligible pool." Built here rather than in
    /// the view so the same sentence appears on every step.
    /// </summary>
    public string ProgressMeter
    {
        get
        {
            var parts = new List<string> { $"{Summary.StepsSet} of {Summary.StepsTotal} set" };
            if (Summary.StepsSkipped > 0) parts.Add($"{Summary.StepsSkipped} skipped");

            var outstanding = Todos
                .Where(t => t.StepCaption is not null)
                .Select(t => t.StepCaption!)
                .Distinct()
                .Take(2)
                .ToList();

            if (outstanding.Count > 0) parts.Add("still to do: " + string.Join(", ", outstanding));

            return string.Join(" · ", parts);
        }
    }
}

public sealed record ProcessTypeOption(
    string ProcessTypeCode, string Name, string? Description, bool AllowsRepeat, int SortOrder);
