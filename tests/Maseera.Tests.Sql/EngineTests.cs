using System.Data;
using Dapper;
using FluentAssertions;

namespace Maseera.Tests.Sql;

/// <summary>
/// The evaluation engine, checked against the rules Part 12 names.
///
/// The single most important correctness rule in the product is that each candidate code
/// is read against its OWN event, its OWN rule and its OWN mapped source. Everything else
/// here follows from it.
/// </summary>
public class EngineTests
{
    private static int? OpenCycle(IDbConnection db)
        => db.ExecuteScalar<int?>("SELECT MAX(CycleId) FROM sel.Cycle");

    [DatabaseFact]
    public void An_equivalent_code_is_met_through_its_own_code_and_the_reason_says_so()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var pair = db.QueryFirstOrDefault<(string MainItemCode, string EquivalentItemCode)>(
            "SELECT TOP (1) MainItemCode, EquivalentItemCode FROM sel.DevEquivalence");
        if (pair.MainItemCode is null) return;

        using var reader = db.QueryMultiple(
            "sel.usp_Item_MetDetail",
            new { LoginName = Database.Hrbp, CycleId = cycleId, ItemCode = pair.MainItemCode, MetOnly = true, PageSize = 500 },
            commandType: CommandType.StoredProcedure);

        var rows = reader.Read<(string PersonnelNo, string FullName, string OrgCode, string? OrgName,
            string? JobTitle, string? GradeCode, bool Met, string? Why, decimal? NumValue,
            decimal? Target, string? ViaCode)>().ToList();

        rows.Should().NotBeEmpty("the fixture gives some people the equivalent code");

        // Every met row names the code that actually satisfied it.
        rows.Should().AllSatisfy(r =>
        {
            r.Met.Should().BeTrue();
            r.Why.Should().NotBeNullOrWhiteSpace("the reason is never optional");
            r.ViaCode.Should().NotBeNullOrWhiteSpace();
        });

        // And at least one of them got there through the equivalent, not the main code.
        rows.Should().Contain(r => r.ViaCode == pair.EquivalentItemCode,
            "an equivalence that never names itself is an equivalence nobody can audit");

        rows.Where(r => r.ViaCode == pair.EquivalentItemCode)
            .Should().AllSatisfy(r => r.Why!.Should().Contain(pair.EquivalentItemCode,
                "the sentence says which code did it"));
    }

    [DatabaseFact]
    public void The_reason_is_present_on_every_requirement_met_or_not()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var person = db.ExecuteScalar<string?>(
            "SELECT TOP (1) PersonnelNo FROM sel.CycleCandidate WHERE CycleId = @cycleId ORDER BY PersonnelNo",
            new { cycleId });
        if (person is null) return;

        using var reader = db.QueryMultiple(
            "sel.usp_Attainment_PerPerson",
            new { LoginName = Database.Hrbp, CycleId = cycleId, PersonnelNo = person },
            commandType: CommandType.StoredProcedure);

        var requirements = reader.Read<(int DevEventId, string ItemCode, string EventCode, string EventName,
            decimal Weight, bool IsMust, int LevelNo, int DevFrameworkId, string FrameworkName,
            bool Met, string? Why, decimal? NumValue, decimal? Target, string? ViaCode, string? RuleShort)>()
            .ToList();

        requirements.Should().NotBeEmpty();
        requirements.Should().AllSatisfy(r => r.Why.Should().NotBeNullOrWhiteSpace(
            $"{r.EventCode} has to say why it is {(r.Met ? "met" : "not met")}"));
    }

    [DatabaseFact]
    public void A_person_percentage_and_the_ladder_agree_with_each_other()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var person = db.ExecuteScalar<string?>(
            "SELECT TOP (1) PersonnelNo FROM sel.CycleCandidate WHERE CycleId = @cycleId ORDER BY PersonnelNo",
            new { cycleId });
        if (person is null) return;

        using var reader = db.QueryMultiple(
            "sel.usp_Attainment_PerPerson",
            new { LoginName = Database.Hrbp, CycleId = cycleId, PersonnelNo = person },
            commandType: CommandType.StoredProcedure);

        reader.Read();   // the requirements
        var attainment = reader.ReadSingle<(string PersonnelNo, decimal? WeightTotal, decimal WeightMet,
            decimal AttainmentPct, int MustOutstanding, int ItemsOutstanding, int InScope)>();
        var ladder = reader.Read<(int CycleReadinessId, string LevelCode, string Name, decimal? ThresholdPct,
            int SortOrder, decimal AttainmentPct, int MustOutstanding, bool IsHeld,
            decimal? ShortByPct, string StateWord)>().ToList();

        ladder.Should().NotBeEmpty("the cycle has readiness levels");

        foreach (var rung in ladder)
        {
            rung.AttainmentPct.Should().Be(attainment.AttainmentPct,
                "the ladder measures the same percentage the summary prints");

            rung.StateWord.Should().NotBeNullOrWhiteSpace();

            if (rung.MustOutstanding > 0)
                rung.IsHeld.Should().BeFalse("a must not met disqualifies whatever the percentage says");
            else if (rung.ThresholdPct is { } threshold)
                rung.IsHeld.Should().Be(rung.AttainmentPct >= threshold);

            // A rung that is held is not also short of its threshold.
            if (rung.IsHeld) rung.ShortByPct.Should().BeNull();
        }
    }

    [DatabaseFact]
    public void Nobody_qualifying_and_the_question_failing_are_different_answers()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var parameters = new DynamicParameters(new { LoginName = Database.Hrbp, CycleId = cycleId, PageSize = 5 });
        parameters.Add("Problem", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        using var reader = db.QueryMultiple("sel.usp_Pool_Preview", parameters, commandType: CommandType.StoredProcedure);
        reader.Read();                    // per-set reach
        reader.Read();                    // the sample page
        var totals = reader.ReadSingle<(int? TotalRows, int? PoolCount, bool IsSampled, string? Problem)>();

        if (totals.Problem is not null)
        {
            // The question could not be asked. A null count is the honest answer, and the
            // screen must not render it as a zero.
            totals.PoolCount.Should().BeNull(
                "a pool that could not be resolved is null, never zero");
        }
        else
        {
            totals.PoolCount.Should().NotBeNull("a resolved pool has a count even when it is zero");
        }
    }

    [DatabaseFact]
    public void A_sampled_figure_says_that_it_was_sampled()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        using var reader = db.QueryMultiple(
            "sel.usp_Framework_Attainment",
            new { LoginName = Database.Hrbp, CycleId = cycleId },
            commandType: CommandType.StoredProcedure);

        var items = reader.Read<(int DevEventId, string ItemCode, string EventCode, string EventName,
            decimal Weight, bool IsMust, int LevelNo, int DevFrameworkId, string? RuleText,
            int MetInSample, int MetCount, int PoolCount, int SampleCount, bool IsSampled)>().ToList();

        var summary = reader.ReadSingle<(int PoolCount, int SampleCount, bool IsSampled, int ItemCount,
            int MustCount, int MetEverything, int ClearAllMandatory, decimal? MedianAttainment,
            string? SampleNote)>();

        if (summary.IsSampled)
        {
            summary.SampleNote.Should().NotBeNullOrWhiteSpace(
                "an estimate that does not say it is an estimate is a lie with a decimal point");
            summary.SampleCount.Should().BeLessThan(summary.PoolCount);
        }
        else
        {
            summary.SampleCount.Should().Be(summary.PoolCount,
                "an unsampled figure counted everybody");
        }

        // A count can never exceed the pool it was counted against, sampled or not.
        items.Should().AllSatisfy(i => i.MetCount.Should().BeLessThanOrEqualTo(i.PoolCount));
    }

    [DatabaseFact]
    public void The_engine_answers_the_whole_pool_in_one_pass_not_one_person_at_a_time()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var poolCount = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM sel.CycleCandidate WHERE CycleId = @cycleId", new { cycleId });
        if (poolCount < 50) return;   // too small to say anything about

        var started = DateTime.UtcNow;

        using (var reader = db.QueryMultiple(
            "sel.usp_Framework_Attainment",
            new { LoginName = Database.Hrbp, CycleId = cycleId },
            commandType: CommandType.StoredProcedure))
        {
            reader.Read();
            reader.Read();
        }

        var elapsed = DateTime.UtcNow - started;

        // A per-person loop over a few hundred people would be seconds, not milliseconds.
        // This is a smoke alarm, not a benchmark: it catches the shape going wrong.
        elapsed.Should().BeLessThan(TimeSpan.FromSeconds(30),
            "the engine is set-based: one statement per candidate code answers the whole pool");
    }

    [DatabaseFact]
    public void The_pool_snapshot_is_written_once_and_not_recomputed()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var status = db.ExecuteScalar<string?>(
            "SELECT sel.fn_CycleStatusCode(@cycleId)", new { cycleId });
        if (status != "ACTIVE") return;

        var before = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM sel.CycleCandidate WHERE CycleId = @cycleId", new { cycleId });

        // Reading the stage does not re-resolve the pool.
        using (var reader = db.QueryMultiple(
            "sel.usp_Stage_Funnel",
            new
            {
                LoginName = Database.Hrbp,
                CycleStageId = db.ExecuteScalar<int>(
                    "SELECT MIN(s.CycleStageId) FROM sel.CycleStage s " +
                    "JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId WHERE p.CycleId = @cycleId",
                    new { cycleId })
            },
            commandType: CommandType.StoredProcedure))
        {
            reader.Read();
        }

        var after = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM sel.CycleCandidate WHERE CycleId = @cycleId", new { cycleId });

        after.Should().Be(before,
            "the pool is resolved at open and never again — a roster change must not move people in or out");
    }

    [DatabaseFact]
    public void A_sensitive_column_is_refused_as_a_filter_and_the_refusal_says_why()
    {
        using var db = Database.Open();
        var cycleId = OpenCycle(db);
        if (cycleId is null) return;

        var sensitive = db.ExecuteScalar<int?>(
            "SELECT TOP (1) RosterFieldId FROM sel.RosterField WHERE IsSensitive = 1 ORDER BY RosterFieldId");
        if (sensitive is null) return;

        using var transaction = db.BeginTransaction();

        var setId = db.ExecuteScalar<int?>(
            "SELECT TOP (1) CriterionSetId FROM sel.CycleCriterionSet WHERE CycleId = @cycleId",
            new { cycleId }, transaction);
        if (setId is null) { transaction.Rollback(); return; }

        var parameters = new DynamicParameters(new
        {
            LoginName = Database.Administrator,
            CriterionSetId = setId,
            RosterFieldId = sensitive,
            OperatorCode = "IS_RECORDED"
        });
        parameters.Add("Problem", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);

        db.Query("sel.usp_Criterion_Save", parameters, transaction, commandType: CommandType.StoredProcedure).ToList();

        var problem = parameters.Get<string?>("Problem");

        problem.Should().NotBeNullOrWhiteSpace("a sensitive column is refused as a filter");
        problem.Should().Contain("sensitive",
            because: "the refusal says why, not just that it will not");

        transaction.Rollback();
    }
}
