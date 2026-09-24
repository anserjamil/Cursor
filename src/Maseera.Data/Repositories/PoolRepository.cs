using Dapper;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class PoolRepository
{
    private readonly IProcRunner _run;

    public PoolRepository(IProcRunner run) => _run = run;

    /// <summary>
    /// The rule read back as sentences with a reach per set, a page of matching people,
    /// and the totals.
    ///
    /// A null PoolCount is not zero: it means the question could not be asked, and
    /// Problem carries the sentence. Distinguish "nobody qualifies" from "the question
    /// could not be asked" — the UI must never render the second as a zero.
    /// </summary>
    public async Task<PoolPreview> PreviewAsync(
        int cycleId, int pageNo = 1, int? pageSize = null, string? search = null,
        CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Pool_Preview", async g =>
        {
            var sets = (await g.ReadAsync<PoolSetReachRow>()).AsList();
            var people = (await g.ReadAsync<PoolPersonRow>()).AsList();
            var totals = await g.ReadFirstOrDefaultAsync<PoolTotals>()
                         ?? new PoolTotals(null, null, false, null);
            return (sets, people, totals);
        }, new { CycleId = cycleId, PageNo = pageNo, PageSize = pageSize, Search = search }, ct);

        return new PoolPreview(value.sets, value.people, value.totals, problem ?? value.totals.Problem);
    }

    /// <summary>
    /// The auditor's answer to "why was this person pooled?": each criterion and the
    /// value that satisfied it, readable without being able to change anything.
    /// </summary>
    public async Task<PoolTrace> TraceAsync(int cycleId, string personnelNo, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Candidate_Trace", async g =>
        {
            var rows = (await g.ReadAsync<CandidateTraceRow>()).AsList();
            var header = await g.ReadFirstOrDefaultAsync<CandidateTraceHeader>();
            return (rows, header);
        }, new { CycleId = cycleId, PersonnelNo = personnelNo }, ct);

        return new PoolTrace(value.rows, value.header, problem);
    }
}

public sealed record PoolPreview(
    IReadOnlyList<PoolSetReachRow> Sets,
    IReadOnlyList<PoolPersonRow> People,
    PoolTotals Totals,
    string? Problem)
{
    /// <summary>
    /// True when the pool resolved to nobody. False when it could not be resolved at all,
    /// which is a different thing and reads differently on screen.
    /// </summary>
    public bool ResolvedToNobody => Problem is null && Totals.PoolCount == 0;

    public bool CouldNotBeAsked => Problem is not null || Totals.PoolCount is null;
}

public sealed record PoolTrace(
    IReadOnlyList<CandidateTraceRow> Rows,
    CandidateTraceHeader? Header,
    string? Problem);
