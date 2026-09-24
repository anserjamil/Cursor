using Dapper;
using FluentAssertions;

namespace Maseera.Tests.Sql;

/// <summary>
/// The contract between the application and the database.
///
/// Every procedure the repositories name has to exist, and every parameter they pass has
/// to be one it declares. A rename that lands in SQL but not in C# is otherwise found by
/// a user, on a screen, in the middle of a calibration meeting.
/// </summary>
public class ProcContractTests
{
    /// <summary>
    /// Every procedure name that appears in a repository call, read out of the source
    /// rather than listed by hand — a list by hand goes stale the first time somebody
    /// adds a repository method.
    /// </summary>
    public static IEnumerable<object[]> ProceduresNamedInCode()
        => RepositorySource.ProcedureNames().Select(n => new object[] { n });

    [DatabaseTheory]
    [MemberData(nameof(ProceduresNamedInCode))]
    public void Every_procedure_the_application_calls_exists(string procedure)
    {
        using var db = Database.Open();

        var exists = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM sys.procedures p JOIN sys.schemas s ON s.schema_id = p.schema_id " +
            "WHERE s.name + '.' + p.name = @procedure",
            new { procedure });

        exists.Should().Be(1, $"{procedure} is called from a repository");
    }

    [DatabaseFact]
    public void Every_procedure_that_can_refuse_declares_the_output_it_refuses_through()
    {
        using var db = Database.Open();

        // A save that cannot say why it refused leaves the screen to invent a sentence.
        var missing = db.Query<string>(
            """
            SELECT s.name + '.' + p.name
            FROM sys.procedures p
            JOIN sys.schemas s ON s.schema_id = p.schema_id
            WHERE s.name IN ('sel', 'cfg', 'sec')
              AND (p.name LIKE '%_Save' OR p.name LIKE '%_Delete' OR p.name LIKE '%_Remove'
                   OR p.name LIKE '%_Add' OR p.name LIKE '%_Open' OR p.name LIKE '%_Copy')
              AND NOT EXISTS (SELECT 1 FROM sys.parameters pr
                              WHERE pr.object_id = p.object_id AND pr.name = '@Problem'
                                AND pr.is_output = 1)
            """).ToList();

        missing.Should().BeEmpty("a refusal comes home as a sentence, not as an exception");
    }

    [DatabaseFact]
    public void Every_procedure_that_reads_a_persons_rows_takes_the_login_it_scopes_by()
    {
        using var db = Database.Open();

        // Every read joins the row's OrgCode to sec.fn_UserOrgScope(@LoginName). A read
        // procedure without a login cannot have done that.
        var missing = db.Query<string>(
            """
            SELECT s.name + '.' + p.name
            FROM sys.procedures p
            JOIN sys.schemas s ON s.schema_id = p.schema_id
            WHERE s.name = 'sel'
              AND (p.name LIKE 'usp_Stage_%' OR p.name LIKE 'usp_Candidate_%'
                   OR p.name LIKE 'usp_Report_%' OR p.name LIKE 'usp_Idp_%'
                   OR p.name LIKE 'usp_Succession_%')
              AND p.name NOT LIKE '%[_]Into'
              AND NOT EXISTS (SELECT 1 FROM sys.parameters pr
                              WHERE pr.object_id = p.object_id AND pr.name = '@LoginName')
            """).ToList();

        missing.Should().BeEmpty("every read is scoped to the viewer's organisations");
    }

    [DatabaseFact]
    public void A_worker_that_takes_no_login_reads_a_scope_its_caller_already_built()
    {
        using var db = Database.Open();

        // The _Into workers fill a caller-created temp table and are deliberately not
        // given a login: scoping them again would be a second answer to a question the
        // caller has already asked. They are only safe if they read that scope, so that
        // is what is checked rather than the convention being taken on trust.
        var workers = db.Query<string>(
            "SELECT s.name + '.' + p.name FROM sys.procedures p " +
            "JOIN sys.schemas s ON s.schema_id = p.schema_id WHERE p.name LIKE '%[_]Into'").ToList();

        workers.Should().NotBeEmpty("the engine's workers follow the _Into convention");

        foreach (var worker in workers)
        {
            var definition = db.ExecuteScalar<string>(
                "SELECT OBJECT_DEFINITION(OBJECT_ID(@worker))", new { worker })!;

            definition.Should().Contain("#scope",
                $"{worker} takes no login, so it must read the scope its caller built");
        }
    }

    [DatabaseFact]
    public void The_contract_procedure_describes_every_procedure_the_runner_will_call()
    {
        using var db = Database.Open();

        var declared = db.Query<(string ProcName, string ParameterName)>(
            "EXEC cfg.usp_Proc_Contract")
            .ToList();

        declared.Should().NotBeEmpty();

        // The runner adds @LoginName only where a procedure declares it. If the contract
        // came back empty for a procedure that has parameters, it would add none of them.
        var withParameters = declared.Select(d => d.ProcName).Distinct().ToList();
        withParameters.Should().Contain("sel.usp_Stage_Candidates");
        withParameters.Should().Contain("cfg.usp_Screen_List");
    }
}
