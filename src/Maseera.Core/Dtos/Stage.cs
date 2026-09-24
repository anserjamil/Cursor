namespace Maseera.Core.Dtos;

/// <summary>Where a stage is against the as-of date, and why it is read-only if it is.</summary>
public sealed record StageStateRow(
    int CycleStageId, int CycleProcessId, int CycleId, string StageKindCode, string RouteKey,
    string? ScreenCode, string StageName, string ProcessName, string ProcessTypeCode,
    DateOnly? StartDate, DateOnly? EndDate, int? PerformerLevelValueId, string? PerformerName,
    string StageState, bool CanWrite, string? LockReason, string? OpenStageName,
    bool IsTestMode, DateOnly AsOf);

public sealed record StageTabRow(
    int CycleProcessId, string ProcessName, int ProcessSort,
    int CycleStageId, string StageName, string RouteKey,
    DateOnly? StartDate, DateOnly? EndDate, int SortOrder,
    string StageState, bool IsCurrent);

/// <summary>
/// One pill of the funnel. The outcome pill is a sum of the boxes that count to the
/// total, not a box of its own, which is why it is flagged rather than special-cased.
/// </summary>
public sealed record FunnelPillRow(
    int FunnelPillId, string PillCode, string Caption, string? Tooltip, int GroupNo,
    string? SemanticRole, bool IsOutcome, bool CountsToTotal, int SortOrder, int Cnt);

/// <summary>
/// A candidate row. The extra roster columns the picker added arrive separately, because
/// the column set is chosen at runtime and cannot be a property on a record.
/// </summary>
public sealed record CandidateRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    string? GradeCode, string? PermJobSuffix, string? PermJobSuffixDesc, string? ManagementLevelCode,
    string SourceCode, string? DecisionCode, string BoxCode,
    string? DecisionName, string? DecisionRole, string? SourceName, string? SourceRole,
    int AlsoInCount);

public sealed record StageTotals(
    int TotalRows, int ShownRows, int PoolCount, int PageNo, int PageSize, decimal? MaxDraw);

public sealed record ColumnValueRow(string? Value, int Cnt);

public sealed record DecisionSaved(
    string PersonnelNo, string FullName, string DecisionCode, string DecisionName,
    string BoxCode, bool IsTest);

public sealed record DecisionLogRow(
    long DecisionId, int CycleId, int? CycleProcessId, int? CycleStageId, string PersonnelNo,
    string? Reason, string ActorLogin, DateTime DecidedOnUtc, bool IsTest,
    string DecisionCode, string DecisionName, string? DecisionRole, string? PerformerName,
    string? FullName, string? OrgCode, string? OrgName,
    string? CycleName, string? CycleCode, string? ProcessName, string? StageName, string? ActorName);

public sealed record DecisionChipRow(string DecisionCode, string DecisionName,
    string? SemanticRole, int SortOrder, int Cnt);

public sealed record AddablePersonRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    string? GradeCode, string SourceCode, bool AlreadyIn);

/// <summary>Advisory only. Nothing here is recorded until somebody decides it themselves.</summary>
public sealed record SuggestionRow(
    string PersonnelNo, string FullName, string OrgCode, string? JobTitle, string? GradeCode,
    decimal Perf, decimal Acting, decimal Courses, decimal Tenure, decimal Assessed, decimal Score,
    string SuggestedDecision, string Because, string Advisory);

public sealed record CandidateTraceRow(
    long CycleCandidateTraceId, int CycleId, string PersonnelNo, int? CriterionId, string? SetLabel,
    string? FieldName, string? OperatorName, string? TestedValue, string? ActualValue,
    bool? Passed, DateTime CapturedOnUtc, string? FieldCaption, string Sentence);

public sealed record CandidateTraceHeader(
    string PersonnelNo, string SourceCode, string OrgCode, DateTime AddedOnUtc,
    string? AddedByLogin, string FullName, DateTime? SnapshotTakenOn);

public sealed record StagePerformerRow(
    int StagePerformerId, int LevelValueId, string LevelCode, string LevelName,
    bool IsActive, int SortOrder, int UsageCount);

public sealed record ManagementLevelRow(int LevelValueId, string LevelCode, string LevelName, int SortOrder);

/* ---- succession ---------------------------------------------------------------- */

public sealed record SuccessionPlanRow(
    long SuccessionPlanRowId, int CycleId, string PersonnelNo, string Department, string? OrgCode,
    string? LevelCode, short PlanYear, string? Remark, string ActorLogin, DateTime DecidedOnUtc,
    bool IsDropped, string FullName, string? JobTitle, string? GradeCode, string? OrgName,
    string? LevelName);

public sealed record SuccessionCensusRow(
    string LevelCode, string Name, decimal? ThresholdPct, int SortOrder, int Planned);

public sealed record SuccessionDepartmentRow(string Department, int Planned);

public sealed record PositionRow(
    string PositionCode, string? IncumbentPersonnelNo, string? IncumbentName, string? OrgCode,
    string? OrgName, string? JobTitle, string? PermJobSuffix, int SuccessorCount);

public sealed record SuccessionSlotRow(
    long SuccessionSlotId, string PositionCode, string? IncumbentPersonnelNo,
    string SuccessorPersonnelNo, string? LevelCode, string? Remark, string ActorLogin,
    DateTime DecidedOnUtc, string SuccessorName, string? JobTitle, string? GradeCode, string? LevelName);

public sealed record PlanCheckHeader(
    long SuccessionPlanRowId, string PersonnelNo, string Department, string? LevelCode, string FullName);

public sealed record PlanCheckDepartmentRow(
    string? Department, decimal DaysServed, bool IsPlannedDepartment, int SpreadAcross);

public sealed record PlanCheckVerdict(
    decimal DaysInPlannedDepartment, decimal DaysEverywhere, string Sentence);

public sealed record ReadinessHistoryRow(short HistoryYear, string? LevelCode, int? CycleId, string? CycleName);
