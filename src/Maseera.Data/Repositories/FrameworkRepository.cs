using Dapper;
using Maseera.Core;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class FrameworkRepository
{
    private readonly IProcRunner _run;

    public FrameworkRepository(IProcRunner run) => _run = run;

    /* ---- events ----------------------------------------------------------------- */

    public Task<IReadOnlyList<DevEventRow>> EventsAsync(
        string? search = null, string? partCode = null, string? typeCode = null,
        bool activeOnly = false, CancellationToken ct = default)
        => _run.ListAsync<DevEventRow>("sel.usp_DevEvent_List",
            new { Search = search, PartCode = partCode, TypeCode = typeCode, ActiveOnly = activeOnly }, ct);

    /// <summary>The "Where completion comes from" panel, in one round trip.</summary>
    public Task<EventRuleDetail> EventDetailAsync(int devEventId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_DevEvent_Detail", async g =>
        {
            var ev = await g.ReadFirstOrDefaultAsync<DevEventDetail>();
            var sets = (await g.ReadAsync<ConditionSetRow>()).AsList();
            var conditions = (await g.ReadAsync<ConditionRow>()).AsList();
            var fields = (await g.ReadAsync<EvidenceColumnRow>()).AsList();
            var equivalents = (await g.ReadAsync<EquivalenceRow>()).AsList();
            return new EventRuleDetail(ev, sets, conditions, fields, equivalents);
        }, new { DevEventId = devEventId }, ct);

    public Task<ProcResult> SaveEventAsync(
        int? devEventId, string eventCode, string name, string? description, string kindCode,
        string? itemCode, string? eventTypeCode, string? partCode, string? measureCode,
        string? phaseCode, string? passValue, decimal? sumFloor, int? validityMonths,
        DateOnly? retiredFrom, bool isActive, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_DevEvent_Save", new
        {
            DevEventId = devEventId, EventCode = eventCode, Name = name, Description = description,
            KindCode = kindCode, ItemCode = itemCode, EventTypeCode = eventTypeCode,
            PartCode = partCode, MeasureCode = measureCode, PhaseCode = phaseCode,
            PassValue = passValue, SumFloor = sumFloor, ValidityMonths = validityMonths,
            RetiredFrom = retiredFrom, IsActive = isActive
        }, ct);

    public Task<ProcResult> DeleteEventAsync(int devEventId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_DevEvent_Delete", new { DevEventId = devEventId }, ct);

    /* ---- the completion rule ---------------------------------------------------- */

    public Task<ProcResult> SaveConditionSetAsync(
        int devEventId, int? setId, string setModeCode, string? setJoinCode, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EventConditionSet_Save", new
        {
            DevEventId = devEventId, SetId = setId, SetModeCode = setModeCode, SetJoinCode = setJoinCode
        }, ct);

    public Task<ProcResult> DeleteConditionSetAsync(int setId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EventConditionSet_Delete", new { SetId = setId }, ct);

    public Task<ProcResult> SaveConditionAsync(
        int setId, int? conditionId, string? fieldName, string? operatorCode,
        string? value1, string? value2, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EventCondition_Save", new
        {
            SetId = setId, ConditionId = conditionId, FieldName = fieldName,
            OperatorCode = operatorCode, Value1 = value1, Value2 = value2
        }, ct);

    public Task<ProcResult> DeleteConditionAsync(int conditionId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EventCondition_Delete", new { ConditionId = conditionId }, ct);

    /// <summary>The one-click revert an override offers.</summary>
    public Task<ProcResult> RevertRuleAsync(int devEventId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EventRule_Revert", new { DevEventId = devEventId }, ct);

    public Task<ProcResult> AddEquivalenceAsync(
        string mainItemCode, string equivalentItemCode, string? note, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Equivalence_Add", new
        {
            MainItemCode = mainItemCode, EquivalentItemCode = equivalentItemCode, Note = note
        }, ct);

    public Task<ProcResult> RemoveEquivalenceAsync(int devEquivalenceId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Equivalence_Remove", new { DevEquivalenceId = devEquivalenceId }, ct);

    /* ---- frameworks ------------------------------------------------------------- */

    public Task<IReadOnlyList<FrameworkRow>> ListAsync(
        string? search = null, bool activeOnly = false, CancellationToken ct = default)
        => _run.ListAsync<FrameworkRow>("sel.usp_Framework_List",
            new { Search = search, ActiveOnly = activeOnly }, ct);

    public Task<FrameworkEditor> DetailAsync(int devFrameworkId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Framework_Detail", async g =>
        {
            var header = await g.ReadFirstOrDefaultAsync<FrameworkDetail>();
            var items = (await g.ReadAsync<FrameworkItemRow>()).AsList();
            var mixture = (await g.ReadAsync<MixtureRow>()).AsList();
            return new FrameworkEditor(header, items, mixture);
        }, new { DevFrameworkId = devFrameworkId }, ct);

    public Task<ProcResult> SaveAsync(
        int? devFrameworkId, string frameworkCode, string name, string? description,
        string statusCode, bool usesLevels, int? mixtureModelId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Framework_Save", new
        {
            DevFrameworkId = devFrameworkId, FrameworkCode = frameworkCode, Name = name,
            Description = description, StatusCode = statusCode, UsesLevels = usesLevels,
            MixtureModelId = mixtureModelId
        }, ct);

    public Task<ProcResult> SaveItemAsync(
        int devFrameworkId, int? devFrameworkItemId, int devEventId, int levelNo,
        string? levelName, decimal weight, bool isMust, int? sortOrder, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Framework_SaveItem", new
        {
            DevFrameworkId = devFrameworkId, DevFrameworkItemId = devFrameworkItemId,
            DevEventId = devEventId, LevelNo = levelNo, LevelName = levelName,
            Weight = weight, IsMust = isMust, SortOrder = sortOrder
        }, ct);

    public Task<ProcResult> DeleteItemAsync(int devFrameworkItemId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Framework_DeleteItem", new { DevFrameworkItemId = devFrameworkItemId }, ct);

    /// <summary>Removing a level moves its requirements to the first, rather than losing them.</summary>
    public Task<ProcResult> RemoveLevelAsync(int devFrameworkId, int levelNo, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Framework_RemoveLevel",
            new { DevFrameworkId = devFrameworkId, LevelNo = levelNo }, ct);

    public Task<ProcResult> DuplicateAsync(
        int devFrameworkId, string newCode, string newName, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Framework_Duplicate",
            new { DevFrameworkId = devFrameworkId, NewCode = newCode, NewName = newName }, ct);

    public Task<ProcResult> RetireAsync(int devFrameworkId, DateOnly? retiredOn, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Framework_Retire",
            new { DevFrameworkId = devFrameworkId, RetiredOn = retiredOn }, ct);

    /* ---- mixture models --------------------------------------------------------- */

    public Task<(IReadOnlyList<MixtureModelRow> Models, IReadOnlyList<MixturePartRow> Parts)>
        MixtureModelsAsync(CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_MixtureModel_List", async g =>
        {
            var models = (await g.ReadAsync<MixtureModelRow>()).AsList();
            var parts = (await g.ReadAsync<MixturePartRow>()).AsList();
            return ((IReadOnlyList<MixtureModelRow>)models, (IReadOnlyList<MixturePartRow>)parts);
        }, ct: ct);

    public Task<ProcResult> SaveMixtureModelAsync(
        int? mixtureModelId, string modelCode, string name, string? description,
        decimal tolerancePct, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_MixtureModel_Save", new
        {
            MixtureModelId = mixtureModelId, ModelCode = modelCode, Name = name,
            Description = description, TolerancePct = tolerancePct
        }, ct);

    public Task<ProcResult> SaveMixturePartAsync(
        int mixtureModelId, string partCode, decimal targetPct, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_MixturePart_Save",
            new { MixtureModelId = mixtureModelId, PartCode = partCode, TargetPct = targetPct }, ct);

    /* ---- data sources ----------------------------------------------------------- */

    public Task<(IReadOnlyList<EvidenceSourceRow> Sources, IReadOnlyList<EvidenceSourceColumnRow> Columns)>
        EvidenceSourcesAsync(CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_EvidenceSource_List", async g =>
        {
            var sources = (await g.ReadAsync<EvidenceSourceRow>()).AsList();
            var columns = (await g.ReadAsync<EvidenceSourceColumnRow>()).AsList();
            return ((IReadOnlyList<EvidenceSourceRow>)sources, (IReadOnlyList<EvidenceSourceColumnRow>)columns);
        }, ct: ct);

    public Task<ProcResult> SaveEvidenceSourceAsync(
        string kindCode, string? sourceKey, string? itemColumn, string? statusColumn,
        string? passValue, string? measureColumn, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EvidenceSource_Save", new
        {
            KindCode = kindCode, SourceKey = sourceKey, ItemColumn = itemColumn,
            StatusColumn = statusColumn, PassValue = passValue, MeasureColumn = measureColumn
        }, ct);

    /// <summary>A field typed once becomes a suggestion for every event after.</summary>
    public Task<ProcResult> LearnColumnAsync(
        string kindCode, string columnName, string? dataType = null, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_EvidenceSourceColumn_Learn",
            new { KindCode = kindCode, ColumnName = columnName, DataType = dataType }, ct);

    /* ---- the engine's answers --------------------------------------------------- */

    /// <summary>
    /// Pool-wide attainment, worst-first, with the headline figures. Above the sampling
    /// cap the figures come off a sample and Summary.SampleNote says so.
    /// </summary>
    public Task<(IReadOnlyList<AttainmentItemRow> Items, AttainmentSummary Summary)> AttainmentAsync(
        int cycleId, int? devFrameworkId = null, int? levelNo = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Framework_Attainment", async g =>
        {
            var items = (await g.ReadAsync<AttainmentItemRow>()).AsList();
            var summary = await g.ReadFirstOrDefaultAsync<AttainmentSummary>()
                          ?? new AttainmentSummary(0, 0, false, 0, 0, 0, 0, null, null);
            return ((IReadOnlyList<AttainmentItemRow>)items, summary);
        }, new { CycleId = cycleId, DevFrameworkId = devFrameworkId, LevelNo = levelNo }, ct);

    /// <summary>The drilldown behind a coverage count: exactly the rows that count counted.</summary>
    public Task<(IReadOnlyList<ItemMetPersonRow> People, ItemMetTotals Totals)> ItemDetailAsync(
        int cycleId, string itemCode, bool metOnly = true, int pageNo = 1, int? pageSize = null,
        CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Item_MetDetail", async g =>
        {
            var people = (await g.ReadAsync<ItemMetPersonRow>()).AsList();
            var totals = await g.ReadFirstOrDefaultAsync<ItemMetTotals>() ?? new ItemMetTotals(0, 0, 0);
            return ((IReadOnlyList<ItemMetPersonRow>)people, totals);
        }, new
        {
            CycleId = cycleId, ItemCode = itemCode, MetOnly = metOnly,
            PageNo = pageNo, PageSize = pageSize
        }, ct);

    /// <summary>Where the pool falls today, counting each person at the highest level they clear.</summary>
    public Task<(IReadOnlyList<ReadinessSpreadRow> Levels, ReadinessSpreadSummary Summary)> ReadinessSpreadAsync(
        int cycleId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Readiness_Spread", async g =>
        {
            var levels = (await g.ReadAsync<ReadinessSpreadRow>()).AsList();
            var summary = await g.ReadFirstOrDefaultAsync<ReadinessSpreadSummary>()
                          ?? new ReadinessSpreadSummary(0, 0, false, 0, 0, null);
            return ((IReadOnlyList<ReadinessSpreadRow>)levels, summary);
        }, new { CycleId = cycleId }, ct);

    /// <summary>One person's percentage, their requirement checklist and their ladder.</summary>
    public Task<PersonLadder> PersonLadderAsync(int cycleId, string personnelNo, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Attainment_PerPerson", async g =>
        {
            var requirements = (await g.ReadAsync<PersonRequirementRow>()).AsList();
            var attainment = await g.ReadFirstOrDefaultAsync<PersonAttainment>();
            var ladder = (await g.ReadAsync<LadderRow>()).AsList();
            return new PersonLadder(requirements, attainment, ladder);
        }, new { CycleId = cycleId, PersonnelNo = personnelNo }, ct);
}

public sealed record EventRuleDetail(
    DevEventDetail? Event,
    IReadOnlyList<ConditionSetRow> Sets,
    IReadOnlyList<ConditionRow> Conditions,
    IReadOnlyList<EvidenceColumnRow> Fields,
    IReadOnlyList<EquivalenceRow> Equivalents);

public sealed record FrameworkEditor(
    FrameworkDetail? Framework,
    IReadOnlyList<FrameworkItemRow> Items,
    IReadOnlyList<MixtureRow> Mixture);

public sealed record PersonLadder(
    IReadOnlyList<PersonRequirementRow> Requirements,
    PersonAttainment? Attainment,
    IReadOnlyList<LadderRow> Ladder);
