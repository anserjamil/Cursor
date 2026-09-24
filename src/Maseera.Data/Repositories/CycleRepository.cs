using Dapper;
using Maseera.Core;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class CycleRepository
{
    private readonly IProcRunner _run;

    public CycleRepository(IProcRunner run) => _run = run;

    /// <summary>The operational home and the design list, with the five tracks per cycle.</summary>
    public Task<(IReadOnlyList<CycleRow> Cycles, IReadOnlyList<CycleTrackRow> Tracks)> ListAsync(
        string? statusCode = null, string? search = null, bool mineOnly = false,
        CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Cycle_List", async g =>
        {
            var cycles = (await g.ReadAsync<CycleRow>()).AsList();
            var tracks = (await g.ReadAsync<CycleTrackRow>()).AsList();
            return ((IReadOnlyList<CycleRow>)cycles, (IReadOnlyList<CycleTrackRow>)tracks);
        }, new { StatusCode = statusCode, Search = search, MineOnly = mineOnly }, ct);

    /// <summary>
    /// The stage strip per process, and the one stage each cycle is waiting on — which is
    /// what the single primary action on the Cycles screen points at.
    /// </summary>
    public Task<(IReadOnlyList<CycleSpineRow> Stages, IReadOnlyList<CycleWaitingRow> Waiting)> SpineAsync(
        int? cycleId = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Cycle_Spine", async g =>
        {
            var stages = (await g.ReadAsync<CycleSpineRow>()).AsList();
            var waiting = (await g.ReadAsync<CycleWaitingRow>()).AsList();
            return ((IReadOnlyList<CycleSpineRow>)stages, (IReadOnlyList<CycleWaitingRow>)waiting);
        }, new { CycleId = cycleId }, ct);

    /// <summary>Everything one wizard step needs about a design, in a single round trip.</summary>
    public Task<CycleDetail> DetailAsync(int cycleId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Cycle_Detail", async g =>
        {
            var cycle = await g.ReadFirstOrDefaultAsync<CycleDetailRow>();
            var steps = (await g.ReadAsync<WizardStepRow>()).AsList();
            var sets = (await g.ReadAsync<CriterionSetRow>()).AsList();
            var criteria = (await g.ReadAsync<CriterionRow>()).AsList();
            var frameworks = (await g.ReadAsync<CycleFrameworkRow>()).AsList();
            var levels = (await g.ReadAsync<CycleReadinessRow>()).AsList();
            var processes = (await g.ReadAsync<CycleProcessRow>()).AsList();
            var stages = (await g.ReadAsync<CycleStageRow>()).AsList();
            return new CycleDetail(cycle, steps, sets, criteria, frameworks, levels, processes, stages);
        }, new { CycleId = cycleId }, ct);

    public Task<(IReadOnlyList<CycleRecipeRow> Recipes, IReadOnlyList<CycleRow> Copyable)> RecipesAsync(
        CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_CycleRecipe_List", async g =>
        {
            var recipes = (await g.ReadAsync<CycleRecipeRow>()).AsList();
            var copyable = (await g.ReadAsync<CycleRow>()).AsList();
            return ((IReadOnlyList<CycleRecipeRow>)recipes, (IReadOnlyList<CycleRow>)copyable);
        }, ct: ct);

    public Task<ProcResult<JobSuffixRow>> JobSuffixesAsync(bool chiefOnly = true, CancellationToken ct = default)
        => _run.ListWithProblemAsync<JobSuffixRow>("sel.usp_JobSuffix_List", new { ChiefOnly = chiefOnly }, ct);

    /* ---- the wizard's writes ---------------------------------------------------- */

    public Task<ProcResult> SaveAsync(
        int? cycleId, string cycleCode, string name, DateOnly? startDate, DateOnly? endDate,
        string? ownerLogin, string? delegateLogin, string? notes,
        string? incumbentSuffix, string? successorSuffix, string? existingPoolCode,
        bool activeMembersOnly, int? recipeId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Cycle_Save", new
        {
            CycleId = cycleId, CycleCode = cycleCode, Name = name,
            StartDate = startDate, EndDate = endDate, OwnerLogin = ownerLogin,
            DelegateLogin = delegateLogin, Notes = notes,
            IncumbentSuffix = incumbentSuffix, SuccessorSuffix = successorSuffix,
            ExistingPoolCode = existingPoolCode, ActiveMembersOnly = activeMembersOnly,
            RecipeId = recipeId
        }, ct);

    public Task<ProcResult> DeleteAsync(int cycleId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Cycle_Delete", new { CycleId = cycleId }, ct);

    public Task<ProcResult> CancelAsync(int cycleId, string? reason, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Cycle_Cancel", new { CycleId = cycleId, Reason = reason }, ct);

    public Task<ProcResult> CopyAsync(int sourceCycleId, string newCode, string newName, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Cycle_Copy",
            new { SourceCycleId = sourceCycleId, NewCode = newCode, NewName = newName }, ct);

    /// <summary>
    /// Resolves the pool, writes it as a snapshot, starts the first stage, and makes the
    /// draft Active permanently. The snapshot is never recomputed afterwards.
    /// </summary>
    public Task<ProcResult> OpenAsync(int cycleId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Cycle_Open", new { CycleId = cycleId }, ct);

    public Task<ProcResult> AutoScheduleAsync(int cycleId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Cycle_AutoSchedule", new { CycleId = cycleId }, ct);

    public Task<ProcResult> SetStepSkippedAsync(int cycleId, int stepNo, bool isSkipped, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleSkippedStep_Set",
            new { CycleId = cycleId, StepNo = stepNo, IsSkipped = isSkipped }, ct);

    /* ---- criteria --------------------------------------------------------------- */

    public Task<ProcResult> SaveCriterionSetAsync(
        int cycleId, int? criterionSetId, string? setLabel, string setModeCode, string? setJoinCode,
        CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CriterionSet_Save", new
        {
            CycleId = cycleId, CriterionSetId = criterionSetId, SetLabel = setLabel,
            SetModeCode = setModeCode, SetJoinCode = setJoinCode
        }, ct);

    public Task<ProcResult> DeleteCriterionSetAsync(int criterionSetId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CriterionSet_Delete", new { CriterionSetId = criterionSetId }, ct);

    public Task<ProcResult> SaveCriterionAsync(
        int criterionSetId, int? criterionId, int rosterFieldId, string operatorCode,
        string? value1, string? value2, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Criterion_Save", new
        {
            CriterionSetId = criterionSetId, CriterionId = criterionId,
            RosterFieldId = rosterFieldId, OperatorCode = operatorCode,
            Value1 = value1, Value2 = value2
        }, ct);

    public Task<ProcResult> DeleteCriterionAsync(int criterionId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Criterion_Delete", new { CriterionId = criterionId }, ct);

    /* ---- frameworks, levels, processes, stages ---------------------------------- */

    public Task<ProcResult> AssignFrameworkAsync(int cycleId, int devFrameworkId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleFramework_Assign",
            new { CycleId = cycleId, DevFrameworkId = devFrameworkId }, ct);

    public Task<ProcResult> RemoveFrameworkAsync(int cycleId, int devFrameworkId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleFramework_Remove",
            new { CycleId = cycleId, DevFrameworkId = devFrameworkId }, ct);

    public Task<ProcResult> SaveReadinessAsync(
        int cycleId, int? cycleReadinessId, string levelCode, string name,
        decimal? thresholdPct, int? sortOrder, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleReadiness_Save", new
        {
            CycleId = cycleId, CycleReadinessId = cycleReadinessId, LevelCode = levelCode,
            Name = name, ThresholdPct = thresholdPct, SortOrder = sortOrder
        }, ct);

    public Task<ProcResult> DeleteReadinessAsync(int cycleReadinessId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleReadiness_Delete", new { CycleReadinessId = cycleReadinessId }, ct);

    public Task<ProcResult> SaveProcessAsync(
        int cycleId, int? cycleProcessId, string processTypeCode, string? name,
        DateOnly? startDate, DateOnly? endDate, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleProcess_Save", new
        {
            CycleId = cycleId, CycleProcessId = cycleProcessId, ProcessTypeCode = processTypeCode,
            Name = name, StartDate = startDate, EndDate = endDate
        }, ct);

    public Task<ProcResult> DuplicateProcessAsync(int cycleProcessId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleProcess_Duplicate", new { CycleProcessId = cycleProcessId }, ct);

    public Task<ProcResult> RemoveProcessAsync(int cycleProcessId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleProcess_Remove", new { CycleProcessId = cycleProcessId }, ct);

    public Task<ProcResult> SaveStageAsync(
        int cycleProcessId, int? cycleStageId, string? stageKindCode, string? name,
        DateOnly? startDate, DateOnly? endDate, string? performerCode, int? sortOrder,
        CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleStage_Save", new
        {
            CycleProcessId = cycleProcessId, CycleStageId = cycleStageId,
            StageKindCode = stageKindCode, Name = name, StartDate = startDate, EndDate = endDate,
            PerformerCode = performerCode, SortOrder = sortOrder
        }, ct);

    public Task<ProcResult> DeleteStageAsync(int cycleStageId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_CycleStage_Delete", new { CycleStageId = cycleStageId }, ct);

    /* ---- who can perform a stage ------------------------------------------------ */

    public Task<(IReadOnlyList<StagePerformerRow> InUse, IReadOnlyList<ManagementLevelRow> Available)>
        PerformersAsync(CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_StagePerformer_List", async g =>
        {
            var inUse = (await g.ReadAsync<StagePerformerRow>()).AsList();
            var available = (await g.ReadAsync<ManagementLevelRow>()).AsList();
            return ((IReadOnlyList<StagePerformerRow>)inUse, (IReadOnlyList<ManagementLevelRow>)available);
        }, ct: ct);

    public Task<ProcResult> AddPerformerAsync(string levelCode, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_StagePerformer_Add", new { LevelCode = levelCode }, ct);

    public Task<ProcResult> RemovePerformerAsync(string levelCode, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_StagePerformer_Remove", new { LevelCode = levelCode }, ct);

    /* ---- validation ------------------------------------------------------------- */

    public Task<(IReadOnlyList<ValidationTodoRow> Todos, ValidationSummary Summary, IReadOnlyList<CycleTrack> Tracks)>
        ValidateAsync(int cycleId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Cycle_Validate", async g =>
        {
            var todos = (await g.ReadAsync<ValidationTodoRow>()).AsList();
            var summary = await g.ReadFirstOrDefaultAsync<ValidationSummary>()
                          ?? new ValidationSummary(0, false, 0, 0, 0);
            var tracks = (await g.ReadAsync<CycleTrack>()).AsList();
            return ((IReadOnlyList<ValidationTodoRow>)todos, summary, (IReadOnlyList<CycleTrack>)tracks);
        }, new { CycleId = cycleId }, ct);
}

/// <summary>One design, read in a single round trip.</summary>
public sealed record CycleDetail(
    CycleDetailRow? Cycle,
    IReadOnlyList<WizardStepRow> Steps,
    IReadOnlyList<CriterionSetRow> CriterionSets,
    IReadOnlyList<CriterionRow> Criteria,
    IReadOnlyList<CycleFrameworkRow> Frameworks,
    IReadOnlyList<CycleReadinessRow> Levels,
    IReadOnlyList<CycleProcessRow> Processes,
    IReadOnlyList<CycleStageRow> Stages);
