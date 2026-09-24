namespace Maseera.Core.Dtos;

/// <summary>
/// A development event. RuleShort comes from sel.fn_EventRuleShort — it is never composed
/// in C#, because that is how a list and its rule drift apart.
/// </summary>
public sealed record DevEventRow(
    int DevEventId, string EventCode, string Name, string? Description, string KindCode,
    string KindName, string EvalModeCode, string? ItemCode, string? PassValue, decimal? SumFloor,
    int? ValidityMonths, DateOnly? RetiredFrom, bool IsActive,
    string? EventTypeCode, string? EventTypeName, string? PartCode, string? PartName,
    string? MeasureCode, string? MeasureName, string? PhaseCode, string? PhaseName,
    string? RuleShort, int EquivalentCount, int FrameworkCount, bool SourceIsMapped);

/// <summary>The "Where completion comes from" panel, for one event.</summary>
public sealed record DevEventDetail(
    int DevEventId, string EventCode, string Name, string? Description, string KindCode,
    string KindName, string EvalModeCode, string? DefaultRuleText, string? ItemCode,
    string? PassValue, decimal? SumFloor, int? ValidityMonths, DateOnly? RetiredFrom, bool IsActive,
    int? EventTypeValueId, int? PartValueId, int? MeasureValueId, int? PhaseValueId,
    string? RuleText, string? RuleShort,
    int? EvidenceSourceId, string? AppSchema, string? AppTable, string? ItemColumn,
    string? MeasureColumn, string? StatusColumn, bool SourceIsMapped,
    int SetCount, bool FollowsKindDefault, string? UnmappedWarning);

public sealed record ConditionSetRow(
    int SetId, int DevEventId, string SetLabel, int SortOrder,
    int SetModeValueId, string SetModeCode, string SetModeName,
    int? SetJoinValueId, string? SetJoinCode, string? SetJoinName);

public sealed record ConditionRow(
    int ConditionId, int SetId, string? FieldName, string? OperatorCode, string? OperatorName,
    byte? Arity, string? Value1, string? Value2, int SortOrder, string? Phrase);

/// <summary>
/// A field a condition may name, with the operator it proposes. Never carry over an
/// operator that reads as nonsense ("Status is at least 90").
/// </summary>
public sealed record EvidenceColumnRow(
    int EvidenceSourceColumnId, string ColumnName, string? Caption, string DataType,
    bool IsExpiryDate, bool IsPhysical, bool IsLearned, int UsageCount, string ProposedOperator);

public sealed record EquivalenceRow(
    int DevEquivalenceId, string MainItemCode, string EquivalentItemCode, string? Note,
    string? EquivName, string? EquivKind);

public sealed record FrameworkRow(
    int DevFrameworkId, string FrameworkCode, string Name, string? Description, int VersionNo,
    bool UsesLevels, int? MixtureModelId, string? MixtureModelName, bool IsActive,
    DateOnly? RetiredOn, int StatusValueId, string StatusCode, string StatusName, string? StatusRole,
    int EventCount, int LevelCount, int CycleCount, decimal? WeightTotal);

public sealed record FrameworkDetail(
    int DevFrameworkId, string FrameworkCode, string Name, string? Description, int VersionNo,
    bool UsesLevels, int? MixtureModelId, string? MixtureModelName, decimal? TolerancePct,
    bool IsActive, DateOnly? RetiredOn, int StatusValueId, string StatusCode, string StatusName,
    decimal? WeightTarget, decimal? WeightTotal);

public sealed record FrameworkItemRow(
    int DevFrameworkItemId, int DevFrameworkId, int LevelNo, string? LevelName, int DevEventId,
    decimal Weight, bool IsMust, int SortOrder, string EventCode, string EventName,
    string KindCode, string? ItemCode, string? PartCode, string? PartName, string? RuleShort,
    bool WarnZeroWeight, bool WarnInactive);

/// <summary>The stacked bar against the model marker, with the gap named.</summary>
public sealed record MixtureRow(
    int PartValueId, string PartCode, string PartName, decimal TargetPct,
    decimal ActualWeight, decimal ActualPct, decimal Tolerance)
{
    public decimal Gap => ActualPct - TargetPct;
    public bool WithinTolerance => Math.Abs(Gap) <= Tolerance;
}

public sealed record MixtureModelRow(
    int MixtureModelId, string ModelCode, string Name, string? Description,
    decimal TolerancePct, bool IsActive, int SortOrder, decimal? PartTotal, int UsedBy);

public sealed record MixturePartRow(
    int MixturePartId, int MixtureModelId, int PartValueId, string PartCode,
    string PartName, decimal TargetPct, int SortOrder);

/// <summary>
/// Each evidence source states its own join in a sentence built from the live values, so
/// the sentence cannot drift from the rule it describes.
/// </summary>
public sealed record EvidenceSourceRow(
    int EvidenceSourceId, string KindCode, string KindName, string EvalModeCode,
    string? SourceKey, string AppSchema, string AppTable, string KeyColumn, string? ItemColumn,
    string? StatusColumn, string? PassValue, string? MeasureColumn,
    bool IsMapped, long? RowCountCached, DateTime? LastSyncUtc,
    string? SourceTable, bool SourceIsMapped, int ItemCount, int EventCount,
    string JoinSentence, string? Warning);

public sealed record EvidenceSourceColumnRow(
    int EvidenceSourceColumnId, int EvidenceSourceId, string KindCode, string ColumnName,
    string? Caption, string DataType, bool IsExpiryDate, bool IsPhysical, bool IsLearned,
    int UsageCount, int SortOrder);

public sealed record CatalogItemRow(
    int CatalogItemId, string ItemCode, string Name, string KindCode, string KindName,
    int? CategoryValueId, string? CategoryCode, string? CategoryName,
    bool NeedsReview, bool IsActive, DateTime FirstSeenUtc, int RecordCount);

/* ---- the engine's answers ------------------------------------------------------ */

/// <summary>
/// One item's attainment across the pool. MetCount is scaled back to the pool when the
/// figures came off a sample, and IsSampled says whether that happened.
/// </summary>
public sealed record AttainmentItemRow(
    int DevEventId, string ItemCode, string EventCode, string EventName,
    decimal Weight, bool IsMust, int LevelNo, int DevFrameworkId,
    string? RuleText, int MetInSample, int MetCount, int PoolCount, int SampleCount, bool IsSampled);

public sealed record AttainmentSummary(
    int PoolCount, int SampleCount, bool IsSampled, int ItemCount, int MustCount,
    int MetEverything, int ClearAllMandatory, decimal? MedianAttainment, string? SampleNote);

/// <summary>One requirement on one person's ladder, with the reason on every row.</summary>
public sealed record PersonRequirementRow(
    int DevEventId, string ItemCode, string EventCode, string EventName, decimal Weight,
    bool IsMust, int LevelNo, int DevFrameworkId, string FrameworkName,
    bool Met, string? Why, decimal? NumValue, decimal? Target, string? ViaCode, string? RuleShort);

public sealed record PersonAttainment(
    string PersonnelNo, decimal? WeightTotal, decimal WeightMet, decimal AttainmentPct,
    int MustOutstanding, int ItemsOutstanding, int InScope);

/// <summary>
/// A rung of the readiness ladder: what it asks, and how far along the person is.
/// A "must" not met disqualifies outright, whatever the percentage says.
/// </summary>
public sealed record LadderRow(
    int CycleReadinessId, string LevelCode, string Name, decimal? ThresholdPct, int SortOrder,
    decimal AttainmentPct, int MustOutstanding, bool IsHeld, decimal? ShortByPct, string StateWord);

public sealed record ReadinessSpreadRow(
    int CycleReadinessId, string LevelCode, string Name, decimal? ThresholdPct, int SortOrder,
    int ClearCutInSample, int ClearCut, int AtThisLevel,
    int PoolCount, int SampleCount, bool IsSampled);

public sealed record ReadinessSpreadSummary(
    int PoolCount, int SampleCount, bool IsSampled, int NoLevelYet, int Disqualified, string? SampleNote);

public sealed record ItemMetPersonRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    string? GradeCode, bool Met, string? Why, decimal? NumValue, decimal? Target, string? ViaCode);

public sealed record ItemMetTotals(int TotalRows, int MetCount, int PoolCount);
