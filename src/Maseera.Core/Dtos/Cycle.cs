namespace Maseera.Core.Dtos;

public sealed record CycleRow(
    int CycleId, string CycleCode, string Name, DateOnly? StartDate, DateOnly? EndDate,
    string OwnerLogin, string? DelegateLogin, string? Notes,
    string? IncumbentSuffix, string? SuccessorSuffix, string? ExistingPoolCode, bool ActiveMembersOnly,
    DateTime? OpenedOnUtc, DateTime? ClosedOnUtc, DateTime? PoolResolvedOnUtc,
    string StatusCode, string StatusName, string? StatusRole,
    string? OwnerName, string? DelegateName,
    int PoolCount, int HighPotentialCount, int CriteriaCount, int LevelCount, int ProcessCount,
    bool CanEdit, string? EditRefusal);

/// <summary>
/// One of the five tracks the design list shows instead of a percentage, so you can see
/// which step is missing without reading a number.
/// </summary>
public sealed record CycleTrackRow(int CycleId, string TrackCode, bool IsSet, int SortOrder);

public sealed record CycleDetailRow(
    int CycleId, string CycleCode, string Name, DateOnly? StartDate, DateOnly? EndDate,
    string OwnerLogin, string? DelegateLogin, string? Notes,
    string? IncumbentSuffix, string? SuccessorSuffix, string? ExistingPoolCode, bool ActiveMembersOnly,
    int? RecipeId, DateTime? OpenedOnUtc, DateTime? ClosedOnUtc, int? PoolCount,
    DateTime? PoolResolvedOnUtc, string StatusCode, string StatusName, string? StatusRole,
    string? OwnerName, string? DelegateName, bool CanEdit, string? EditRefusal,
    string? RecipeCode, bool AsksJobSuffix);

public sealed record WizardStepRow(
    int StepNo, string StepCode, string Caption, string? Description,
    bool IsSkippable, int SortOrder, bool IsSkipped);

public sealed record CriterionSetRow(
    int CriterionSetId, string SetLabel, int SortOrder,
    int SetModeValueId, string SetModeCode, string SetModeName,
    int? SetJoinValueId, string? SetJoinCode, string? SetJoinName);

public sealed record CriterionRow(
    int CriterionId, int CriterionSetId, int RosterFieldId, string FieldName, string FieldCaption,
    string DataType, string SourceKind, string OperatorCode, string OperatorName, byte Arity,
    string? Value1, string? Value2, int SortOrder, string Phrase);

public sealed record CycleFrameworkRow(
    int CycleFrameworkId, int DevFrameworkId, string FrameworkCode, string Name,
    int VersionNo, bool UsesLevels, string StatusCode, string StatusName,
    int EventCount, int LevelCount);

public sealed record CycleReadinessRow(
    int CycleReadinessId, string LevelCode, string Name, decimal? ThresholdPct, int SortOrder);

public sealed record CycleProcessRow(
    int CycleProcessId, string ProcessTypeCode, string ProcessTypeName, bool AllowsRepeat,
    string Name, DateOnly? StartDate, DateOnly? EndDate, int SortOrder);

public sealed record CycleStageRow(
    int CycleStageId, int CycleProcessId, string StageKindCode, string StageKindName, string RouteKey,
    string Name, DateOnly? StartDate, DateOnly? EndDate, int SortOrder,
    int? PerformerLevelValueId, string? PerformerCode, string? PerformerName, string StageState);

/// <summary>What the "New design" chooser offers instead of an empty form.</summary>
public sealed record CycleRecipeRow(
    int RecipeId, string RecipeCode, string Name, string? Description,
    bool AsksJobSuffix, bool IsCopy, int SortOrder,
    string? ProcessSummary, int SkipCount, int StepCount);

public sealed record JobSuffixRow(string PermJobSuffix, string? PermJobSuffixDesc);

/// <summary>A to-do from sel.usp_Cycle_Validate, with the step whose button fixes it.</summary>
public sealed record ValidationTodoRow(
    int ValidationRuleId, string RuleCode, int? StepNo, string Sentence,
    string Severity, int SortOrder, string? StepCaption);

public sealed record ValidationSummary(
    int TotalBlocking, bool IsReadyToOpen, int StepsSet, int StepsTotal, int StepsSkipped);

public sealed record CycleTrack(string TrackCode, bool IsSet, int SortOrder);

/// <summary>The stage strip per process, and the stage each cycle is waiting on.</summary>
public sealed record CycleSpineRow(
    int CycleId, int CycleProcessId, string ProcessTypeCode, string ProcessTypeName,
    string ProcessName, DateOnly? ProcessStart, DateOnly? ProcessEnd, int ProcessSort,
    int? CycleStageId, string? StageKindCode, string? StageKindName, string? RouteKey, string? ScreenCode,
    string? StageName, DateOnly? StartDate, DateOnly? EndDate, int? StageSort,
    int? PerformerLevelValueId, string? PerformerLevelName,
    string? StageState, string? StripState, int DecisionCount);

public sealed record CycleWaitingRow(
    int CycleId, int? WaitingStageId, string? WaitingStageName,
    string? WaitingRouteKey, string? WaitingState);

public sealed record PoolSetReachRow(string SetLabel, string Sentence, int? Reach, int SortOrder);

/// <summary>
/// One person in a list: the pool preview's sample and the roster both fill this, and
/// both procedures therefore select exactly these columns in this order.
/// </summary>
public sealed record PoolPersonRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    string? PermJobSuffix, string? PermJobSuffixDesc, string? GradeCode,
    string? ManagementLevelCode, DateOnly? HireDate, DateOnly? PromotionDate,
    bool IsActive, bool PermChiefInd);

/// <summary>
/// A pool count that is null is not zero: it means the question could not be asked, and
/// Problem says why. The view must never render it as a zero.
/// </summary>
public sealed record PoolTotals(int? TotalRows, int? PoolCount, bool IsSampled, string? Problem);
