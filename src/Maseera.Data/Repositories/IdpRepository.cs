using Dapper;
using Maseera.Core;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class IdpRepository
{
    private readonly IProcRunner _run;

    public IdpRepository(IProcRunner run) => _run = run;

    /// <summary>The Overview tab: the progress board, in one round trip.</summary>
    public async Task<IdpBoard> BoardAsync(int cycleStageId, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Idp_Board", async g =>
        {
            var summary = await g.ReadFirstOrDefaultAsync<IdpBoardSummary>();
            var byLevel = (await g.ReadAsync<IdpByLevelRow>()).AsList();
            var byOrg = (await g.ReadAsync<IdpByOrgRow>()).AsList();
            var byEvent = (await g.ReadAsync<IdpByEventRow>()).AsList();
            var attention = (await g.ReadAsync<IdpAttentionRow>()).AsList();
            return new IdpBoard(summary, byLevel, byOrg, byEvent, attention, null);
        }, new { CycleStageId = cycleStageId }, ct);

        return value with { Problem = problem };
    }

    /// <summary>One person's whole plan: every requirement, met ones included but greyed.</summary>
    public async Task<IdpPersonPlan> PersonAsync(
        int cycleStageId, string personnelNo, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Idp_Person", async g =>
        {
            var header = await g.ReadFirstOrDefaultAsync<IdpPersonHeader>();
            var items = (await g.ReadAsync<IdpPersonItemRow>()).AsList();
            var sessions = (await g.ReadAsync<IdpSessionOptionRow>()).AsList();
            var coverage = (await g.ReadAsync<IdpCoverageRow>()).AsList();
            var notes = (await g.ReadAsync<IdpNoteRow>()).AsList();
            return new IdpPersonPlan(header, items, sessions, coverage, notes, null);
        }, new { CycleStageId = cycleStageId, PersonnelNo = personnelNo }, ct);

        return value with { Problem = problem };
    }

    /// <summary>
    /// The open obligations across the cohort, one row per person and event, with both
    /// sources named when two of them ask for the same thing.
    /// </summary>
    public Task<(IReadOnlyList<IdpRequirementRow> Rows, int TotalRows)> RequirementsAsync(
        int cycleStageId, int? devEventId = null, string? search = null, bool openOnly = true,
        int pageNo = 1, int? pageSize = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Idp_Requirements", async g =>
        {
            var rows = (await g.ReadAsync<IdpRequirementRow>()).AsList();
            var total = await g.ReadFirstOrDefaultAsync<int?>() ?? 0;
            return ((IReadOnlyList<IdpRequirementRow>)rows, total);
        }, new
        {
            CycleStageId = cycleStageId, DevEventId = devEventId, Search = search,
            OpenOnly = openOnly, PageNo = pageNo, PageSize = pageSize
        }, ct);

    /* ---- sessions and booking --------------------------------------------------- */

    public Task<IReadOnlyList<IdpSessionRow>> SessionsAsync(
        int? devEventId = null, int? cycleId = null, DateOnly? fromDate = null, CancellationToken ct = default)
        => _run.ListAsync<IdpSessionRow>("sel.usp_Idp_Session_List",
            new { DevEventId = devEventId, CycleId = cycleId, FromDate = fromDate }, ct);

    public Task<ProcResult> SaveSessionAsync(
        int? devSessionId, int devEventId, string sessionCode, DateOnly? startDate, DateOnly? endDate,
        int? seats, string? location, bool isCancelled, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_Session_Save", new
        {
            DevSessionId = devSessionId, DevEventId = devEventId, SessionCode = sessionCode,
            StartDate = startDate, EndDate = endDate, Seats = seats,
            Location = location, IsCancelled = isCancelled
        }, ct);

    /// <summary>
    /// Books people onto a session. Seats are respected, and an over-booking is refused
    /// with a sentence naming how many places are left.
    /// </summary>
    public Task<ProcResult> BookAsync(
        int cycleStageId, int devSessionId, IEnumerable<string> people, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_BookMany", new
        {
            CycleStageId = cycleStageId, DevSessionId = devSessionId, People = TableValued.Ids(people)
        }, ct);

    /// <summary>"Pencil in a date" where no session exists.</summary>
    public Task<ProcResult> PencilAsync(
        int cycleStageId, int devEventId, DateOnly pencilledDate, IEnumerable<string> people,
        CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_PencilMany", new
        {
            CycleStageId = cycleStageId, DevEventId = devEventId,
            PencilledDate = pencilledDate, People = TableValued.Ids(people)
        }, ct);

    /// <summary>
    /// The one-click plan. It returns what it did as a list of sentences, and it never
    /// assigns coverage, because coverage costs leave and is a human decision.
    /// </summary>
    public async Task<IdpSuggestResult> SuggestAsync(
        int cycleStageId, string? personnelNo = null, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Idp_Suggest", async g =>
        {
            var sentences = (await g.ReadAsync<IdpSuggestionSentence>()).AsList();
            var changed = await g.ReadFirstOrDefaultAsync<int?>() ?? 0;
            return (sentences, changed);
        }, new { CycleStageId = cycleStageId, PersonnelNo = personnelNo }, ct);

        return new IdpSuggestResult(value.sentences, value.changed, problem);
    }

    /* ---- coverage --------------------------------------------------------------- */

    public Task<ProcResult> AddCoverageAsync(
        int cycleStageId, string personnelNo, int? devEventId, string? department,
        string? positionCode, string? incumbentPersonnelNo, DateOnly startDate, DateOnly endDate,
        CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_Coverage_Add", new
        {
            CycleStageId = cycleStageId, PersonnelNo = personnelNo, DevEventId = devEventId,
            Department = department, PositionCode = positionCode,
            IncumbentPersonnelNo = incumbentPersonnelNo, StartDate = startDate, EndDate = endDate
        }, ct);

    public Task<ProcResult> RemoveCoverageAsync(long idpCoverageId, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_Coverage_Remove", new { IdpCoverageId = idpCoverageId }, ct);

    public Task<(IReadOnlyList<IdpCoverageBoardRow> Assignments, IReadOnlyList<IdpSuccessorRow> Successors)>
        CoverageBoardAsync(int cycleStageId, string? search = null, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Idp_Coverage_Board", async g =>
        {
            var assignments = (await g.ReadAsync<IdpCoverageBoardRow>()).AsList();
            var successors = (await g.ReadAsync<IdpSuccessorRow>()).AsList();
            return ((IReadOnlyList<IdpCoverageBoardRow>)assignments, (IReadOnlyList<IdpSuccessorRow>)successors);
        }, new { CycleStageId = cycleStageId, Search = search }, ct);

    /* ---- conflicts, notes, target, approval ------------------------------------- */

    public Task<IReadOnlyList<IdpConflictRow>> ConflictsAsync(
        int cycleStageId, string? personnelNo = null, CancellationToken ct = default)
        => _run.ListAsync<IdpConflictRow>("sel.usp_Idp_Conflicts",
            new { CycleStageId = cycleStageId, PersonnelNo = personnelNo }, ct);

    public Task<ProcResult> SaveTargetAsync(
        int cycleStageId, string personnelNo, DateOnly? targetDate, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_Target_Save", new
        {
            CycleStageId = cycleStageId, PersonnelNo = personnelNo, TargetDate = targetDate
        }, ct);

    public Task<ProcResult> AddNoteAsync(
        int cycleStageId, string personnelNo, string noteText, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_Note_Add", new
        {
            CycleStageId = cycleStageId, PersonnelNo = personnelNo, NoteText = noteText
        }, ct);

    /// <summary>
    /// Approval is at plan level, never per requirement, and it refuses unless every open
    /// requirement has a booking, a date or coverage days.
    /// </summary>
    public Task<ProcResult> ApproveAsync(
        int cycleStageId, IEnumerable<string> people, CancellationToken ct = default)
        => _run.ExecAsync("sel.usp_Idp_ApproveMany",
            new { CycleStageId = cycleStageId, People = TableValued.Ids(people) }, ct);

    public Task<IReadOnlyList<IdpRiskRow>> RiskAsync(int cycleStageId, CancellationToken ct = default)
        => _run.ListAsync<IdpRiskRow>("sel.usp_Idp_Risk", new { CycleStageId = cycleStageId }, ct);

    /// <summary>
    /// The cohort's plans as one flat result set. It reads the same procedure the screen
    /// reads with paging off, so an export can never disagree with what was on screen.
    /// </summary>
    public Task<IReadOnlyList<IDictionary<string, object?>>> ExportAsync(
        int cycleStageId, CancellationToken ct = default)
        => _run.MultiAsync("sel.usp_Idp_Export", async g =>
        {
            var rows = (await g.ReadAsync()).Cast<IDictionary<string, object?>>().ToList();
            return (IReadOnlyList<IDictionary<string, object?>>)rows;
        }, new { CycleStageId = cycleStageId }, ct);
}

public sealed record IdpBoard(
    IdpBoardSummary? Summary,
    IReadOnlyList<IdpByLevelRow> ByLevel,
    IReadOnlyList<IdpByOrgRow> ByOrg,
    IReadOnlyList<IdpByEventRow> ByEvent,
    IReadOnlyList<IdpAttentionRow> NeedsAttention,
    string? Problem);

public sealed record IdpPersonPlan(
    IdpPersonHeader? Header,
    IReadOnlyList<IdpPersonItemRow> Items,
    IReadOnlyList<IdpSessionOptionRow> Sessions,
    IReadOnlyList<IdpCoverageRow> Coverage,
    IReadOnlyList<IdpNoteRow> Notes,
    string? Problem);

public sealed record IdpSuggestResult(
    IReadOnlyList<IdpSuggestionSentence> Sentences, int Changed, string? Problem);
