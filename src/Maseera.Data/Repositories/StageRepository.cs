using Dapper;
using Maseera.Core;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class StageRepository
{
    private readonly IProcRunner _run;

    public StageRepository(IProcRunner run) => _run = run;

    /// <summary>Where the stage is, why it is read-only if it is, and the whole tab strip.</summary>
    public Task<(StageStateRow? State, IReadOnlyList<StageTabRow> Tabs)> StateAsync(
        int cycleStageId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Stage_State", async g =>
        {
            var state = await g.ReadFirstOrDefaultAsync<StageStateRow>();
            var tabs = (await g.ReadAsync<StageTabRow>()).AsList();
            return (state, (IReadOnlyList<StageTabRow>)tabs);
        }, new { CycleStageId = cycleStageId }, ct);

    /// <summary>
    /// The table, the funnel and the true total in one call.
    ///
    /// The extra roster columns the picker added are returned as loose rows because the
    /// column set is chosen at runtime; the view reads them by name from the dictionary.
    /// </summary>
    public async Task<StagePage> CandidatesAsync(
        int cycleStageId, string? pillCode = null, string? search = null,
        string? columnSet = null, string? filterJson = null,
        string? sortBy = null, string? sortDir = null,
        int pageNo = 1, int? pageSize = null, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Stage_Candidates", async g =>
        {
            var pills = (await g.ReadAsync<FunnelPillRow>()).AsList();

            // Read as a dictionary so the picker's extra columns survive: a record cannot
            // carry properties chosen at runtime.
            var rows = (await g.ReadAsync()).Cast<IDictionary<string, object?>>().ToList();

            var totals = await g.ReadFirstOrDefaultAsync<StageTotals>()
                         ?? new StageTotals(0, 0, 0, pageNo, pageSize ?? 0, null);
            return (pills, rows, totals);
        }, new
        {
            CycleStageId = cycleStageId, PillCode = pillCode, Search = search,
            ColumnSet = columnSet, FilterJson = filterJson,
            SortBy = sortBy, SortDir = sortDir, PageNo = pageNo, PageSize = pageSize
        }, ct);

        return new StagePage(value.pills, value.rows, value.totals, problem);
    }

    public Task<IReadOnlyList<FunnelPillRow>> FunnelAsync(int cycleStageId, CancellationToken ct = default)
        => _run.ListAsync<FunnelPillRow>("sel.usp_Stage_Funnel", new { CycleStageId = cycleStageId }, ct);

    /// <summary>A column filter's value list, with counts, from a procedure rather than the screen.</summary>
    public Task<ProcResult<ColumnValueRow>> ColumnValuesAsync(
        int cycleStageId, string columnName, string? search = null, CancellationToken ct = default)
        => _run.ListWithProblemAsync<ColumnValueRow>("sel.usp_Stage_ColumnValues",
            new { CycleStageId = cycleStageId, ColumnName = columnName, Search = search }, ct);

    /* ---- decisions -------------------------------------------------------------- */

    /// <summary>
    /// One decision or a thousand, through the same door. The people go in as a
    /// table-valued parameter, never as a loop of single calls.
    /// </summary>
    public Task<ProcResult> SaveDecisionAsync(
        int cycleStageId, IEnumerable<string> people, string decisionCode,
        string? reason = null, string? single = null, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Decision_Save", new
        {
            CycleStageId = cycleStageId,
            PersonnelNo = single,
            People = TableValued.Ids(people),
            DecisionCode = decisionCode,
            Reason = reason
        }, ct);

    /// <summary>Clearing is itself a decision, and lands in the log like any other.</summary>
    public Task<ProcResult> ClearDecisionAsync(
        int cycleStageId, IEnumerable<string> people, string? single = null, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Decision_Clear", new
        {
            CycleStageId = cycleStageId, PersonnelNo = single, People = TableValued.Ids(people)
        }, ct);

    public Task<DecisionLog> DecisionLogAsync(
        int? cycleId = null, int? cycleStageId = null, string? personnelNo = null,
        string? decisionCode = null, string? search = null, bool? testOnly = null,
        int pageNo = 1, int? pageSize = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Decision_Log", async g =>
        {
            var rows = (await g.ReadAsync<DecisionLogRow>()).AsList();
            var total = await g.ReadFirstOrDefaultAsync<int?>() ?? 0;
            var chips = (await g.ReadAsync<DecisionChipRow>()).AsList();
            return new DecisionLog(rows, total, chips);
        }, new
        {
            CycleId = cycleId, CycleStageId = cycleStageId, PersonnelNo = personnelNo,
            DecisionCode = decisionCode, Search = search, TestOnly = testOnly,
            PageNo = pageNo, PageSize = pageSize
        }, ct);

    /* ---- add people ------------------------------------------------------------- */

    public Task<IReadOnlyList<AddablePersonRow>> SearchPeopleAsync(
        int cycleStageId, string? search = null, int top = 100, CancellationToken ct = default)
        => _run.ListAsync<AddablePersonRow>("sel.usp_Candidate_Search",
            new { CycleStageId = cycleStageId, Search = search, Top = top }, ct);

    public Task<ProcResult> AddPeopleAsync(
        int cycleStageId, IEnumerable<string> people, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Candidate_AddPeople",
            new { CycleStageId = cycleStageId, People = TableValued.Ids(people) }, ct);

    /* ---- the focus pane and compare --------------------------------------------- */

    /// <summary>Advisory only. This never writes a decision, and the panel says so.</summary>
    public Task<IReadOnlyList<SuggestionRow>> SuggestionsAsync(
        int cycleStageId, int top = 25, CancellationToken ct = default)
        => _run.ListAsync<SuggestionRow>("sel.usp_Candidate_Suggestions",
            new { CycleStageId = cycleStageId, Top = top }, ct);

    public async Task<ProfilePage> ProfileAsync(
        string personnelNo, int? cycleId = null, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Candidate_Profile", async g =>
        {
            var person = await g.ReadFirstOrDefaultAsync<ProfilePerson>();
            var tiles = (await g.ReadAsync<ProfileTile>()).AsList();
            var performance = (await g.ReadAsync<ProfileRating>()).AsList();
            var coverage = (await g.ReadAsync<ProfileCoverage>()).AsList();
            var records = (await g.ReadAsync<ProfileRecord>()).AsList();
            var history = (await g.ReadAsync<ReadinessHistoryRow>()).AsList();
            var decisions = (await g.ReadAsync<ProfileDecision>()).AsList();

            // The ladder only comes back when a cycle was named, because a ladder without
            // a cycle has nothing to be measured against.
            IReadOnlyList<PersonRequirementRow> requirements = Array.Empty<PersonRequirementRow>();
            PersonAttainment? attainment = null;
            IReadOnlyList<LadderRow> ladder = Array.Empty<LadderRow>();
            if (!g.IsConsumed)
            {
                requirements = (await g.ReadAsync<PersonRequirementRow>()).AsList();
                attainment = await g.ReadFirstOrDefaultAsync<PersonAttainment>();
                ladder = (await g.ReadAsync<LadderRow>()).AsList();
            }

            return new ProfilePage(person, tiles, performance, coverage, records, history,
                decisions, requirements, attainment, ladder, null);
        }, new { PersonnelNo = personnelNo, CycleId = cycleId }, ct);

        return value with { Problem = problem };
    }

    public Task<ProcResult<CompareRow>> CompareAsync(
        IEnumerable<string> people, int? cycleId = null, CancellationToken ct = default)
        => _run.ListWithProblemAsync<CompareRow>("sel.usp_Candidate_Compare",
            new { People = TableValued.Ids(people), CycleId = cycleId }, ct);

    /* ---- succession ------------------------------------------------------------- */

    public Task<SuccessionPlans> PlansAsync(
        int cycleStageId, string? search = null, string? department = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Succession_Plans", async g =>
        {
            var rows = (await g.ReadAsync<SuccessionPlanRow>()).AsList();
            var census = (await g.ReadAsync<SuccessionCensusRow>()).AsList();
            var departments = (await g.ReadAsync<SuccessionDepartmentRow>()).AsList();
            return new SuccessionPlans(rows, census, departments);
        }, new { CycleStageId = cycleStageId, Search = search, Department = department }, ct);

    public Task<ProcResult> SavePlanAsync(
        int cycleStageId, string personnelNo, string department, string? levelCode,
        short? planYear, string? remark, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Succession_Plan_Save", new
        {
            CycleStageId = cycleStageId, PersonnelNo = personnelNo, Department = department,
            LevelCode = levelCode, PlanYear = planYear, Remark = remark
        }, ct);

    public Task<ProcResult> BulkAddPlanAsync(
        int cycleStageId, IEnumerable<string> people, string department, string? levelCode,
        CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Succession_Plan_BulkAdd", new
        {
            CycleStageId = cycleStageId, People = TableValued.Ids(people),
            Department = department, LevelCode = levelCode
        }, ct);

    public Task<ProcResult> DropPlanAsync(long planRowId, string? reason, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Succession_Plan_Drop",
            new { SuccessionPlanRowId = planRowId, Reason = reason }, ct);

    public async Task<SuccessionPositions> ByPositionAsync(
        int cycleStageId, string? search = null, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Succession_ByPosition", async g =>
        {
            var positions = (await g.ReadAsync<PositionRow>()).AsList();
            var slots = (await g.ReadAsync<SuccessionSlotRow>()).AsList();
            return (positions, slots);
        }, new { CycleStageId = cycleStageId, Search = search }, ct);

        return new SuccessionPositions(value.positions, value.slots, problem);
    }

    public Task<ProcResult> SaveSlotAsync(
        int cycleStageId, string positionCode, string successorPersonnelNo,
        string? incumbentPersonnelNo, string? levelCode, string? remark, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Succession_Slot_Save", new
        {
            CycleStageId = cycleStageId, PositionCode = positionCode,
            SuccessorPersonnelNo = successorPersonnelNo, IncumbentPersonnelNo = incumbentPersonnelNo,
            LevelCode = levelCode, Remark = remark
        }, ct);

    public Task<ProcResult> RemoveSlotAsync(long slotId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Succession_Slot_Remove", new { SuccessionSlotId = slotId }, ct);

    public Task<ProcResult> SaveReadinessAsync(
        int cycleStageId, long planRowId, string levelCode, string? remark, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Succession_Readiness_Save", new
        {
            CycleStageId = cycleStageId, SuccessionPlanRowId = planRowId,
            LevelCode = levelCode, Remark = remark
        }, ct);

    /// <summary>
    /// The framework requirement met, against the plan-specific rule, showing where the
    /// days were actually served.
    /// </summary>
    public async Task<PlanCheck> PlanCheckAsync(long planRowId, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Succession_PlanCheck", async g =>
        {
            var header = await g.ReadFirstOrDefaultAsync<PlanCheckHeader>();
            var requirements = (await g.ReadAsync<PersonRequirementRow>()).AsList();
            var attainment = await g.ReadFirstOrDefaultAsync<PersonAttainment>();
            var ladder = (await g.ReadAsync<LadderRow>()).AsList();
            var departments = (await g.ReadAsync<PlanCheckDepartmentRow>()).AsList();
            var verdict = await g.ReadFirstOrDefaultAsync<PlanCheckVerdict>();
            return new PlanCheck(header, requirements, attainment, ladder, departments, verdict, null);
        }, new { SuccessionPlanRowId = planRowId }, ct);

        return value with { Problem = problem };
    }
}

/* -------------------------------------------------------------------------------- */

public sealed record StagePage(
    IReadOnlyList<FunnelPillRow> Pills,
    IReadOnlyList<IDictionary<string, object?>> Rows,
    StageTotals Totals,
    string? Problem);

public sealed record DecisionLog(
    IReadOnlyList<DecisionLogRow> Rows, int TotalRows, IReadOnlyList<DecisionChipRow> Chips);

public sealed record SuccessionPlans(
    IReadOnlyList<SuccessionPlanRow> Rows,
    IReadOnlyList<SuccessionCensusRow> Census,
    IReadOnlyList<SuccessionDepartmentRow> Departments);

public sealed record SuccessionPositions(
    IReadOnlyList<PositionRow> Positions,
    IReadOnlyList<SuccessionSlotRow> Slots,
    string? Problem);

public sealed record PlanCheck(
    PlanCheckHeader? Header,
    IReadOnlyList<PersonRequirementRow> Requirements,
    PersonAttainment? Attainment,
    IReadOnlyList<LadderRow> Ladder,
    IReadOnlyList<PlanCheckDepartmentRow> Departments,
    PlanCheckVerdict? Verdict,
    string? Problem);

public sealed record ProfilePage(
    ProfilePerson? Person,
    IReadOnlyList<ProfileTile> Tiles,
    IReadOnlyList<ProfileRating> Performance,
    IReadOnlyList<ProfileCoverage> Coverage,
    IReadOnlyList<ProfileRecord> Records,
    IReadOnlyList<ReadinessHistoryRow> History,
    IReadOnlyList<ProfileDecision> Decisions,
    IReadOnlyList<PersonRequirementRow> Requirements,
    PersonAttainment? Attainment,
    IReadOnlyList<LadderRow> Ladder,
    string? Problem);

public sealed record ProfilePerson(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, byte? OrgLevel,
    string? JobTitle, string? PermJobSuffix, string? PermJobSuffixDesc, string? CurrentJobSuffix,
    string? GradeCode, string? ManagementLevelCode, DateOnly? HireDate, DateOnly? PromotionDate,
    int? AgeYears, decimal? TenureYears, bool IsActive, bool PermChiefInd, string? Email);

public sealed record ProfileTile(
    string MetricKey, string Name, string? Description, decimal? NumValue,
    string? TextValue, DateOnly? AsOfDate, int SortOrder);

public sealed record ProfileRating(short RatingYear, string? RatingCode, decimal? RatingValue, string? RatingRole);

public sealed record ProfileCoverage(
    long EmployeeCoverageId, string? ItemCode, string? CoverageType, string? Department,
    string? OrgCode, string? PositionSuffix, string? PositionCode,
    DateOnly? StartDate, DateOnly? EndDate, decimal? Days, decimal? Months);

public sealed record ProfileRecord(
    long EmployeeRecordId, string KindCode, string KindName, string ItemCode, string? ItemName,
    string? Status, decimal? Score, decimal? MaxScore, DateOnly? CompletedOn, DateOnly? ExpiresOn,
    string? Source, bool IsExpired);

public sealed record ProfileDecision(
    long DecisionId, int CycleId, string? CycleName, string? StageName,
    string DecisionCode, string DecisionName, string? SemanticRole,
    string? Reason, string ActorLogin, DateTime DecidedOnUtc, bool IsTest);

public sealed record CompareRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    string? PermJobSuffix, string? GradeCode, string? ManagementLevelCode,
    DateOnly? HireDate, DateOnly? PromotionDate,
    decimal? PerformanceAvg3, decimal? DaysCovered, decimal? CoursesCompleted, string? LatestDecision);
