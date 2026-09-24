using Dapper;
using FluentAssertions;

namespace Maseera.Tests.Sql;

/// <summary>
/// The migration runs twice without complaint, and the reference data it seeds is a MERGE
/// rather than an INSERT.
///
/// A deployment that only works on an empty database is a deployment nobody dares run.
/// </summary>
public class IdempotencyTests
{
    [DatabaseFact]
    public void Every_configuration_and_reference_table_has_rows()
    {
        using var db = Database.Open();

        var counts = db.Query<(string TableName, int Rows)>(
            """
            SELECT 'cfg.Domain',            COUNT(*) FROM cfg.Domain
            UNION ALL SELECT 'cfg.DomainValue',       COUNT(*) FROM cfg.DomainValue
            UNION ALL SELECT 'cfg.Operator',          COUNT(*) FROM cfg.Operator
            UNION ALL SELECT 'cfg.Setting',           COUNT(*) FROM cfg.Setting
            UNION ALL SELECT 'cfg.Screen',            COUNT(*) FROM cfg.Screen
            UNION ALL SELECT 'cfg.MenuGroup',         COUNT(*) FROM cfg.MenuGroup
            UNION ALL SELECT 'cfg.Message',           COUNT(*) FROM cfg.Message
            UNION ALL SELECT 'sel.RequirementKind',   COUNT(*) FROM sel.RequirementKind
            UNION ALL SELECT 'sel.EvidenceSource',    COUNT(*) FROM sel.EvidenceSource
            UNION ALL SELECT 'sel.TableMapping',      COUNT(*) FROM sel.TableMapping
            UNION ALL SELECT 'sel.ProcessType',       COUNT(*) FROM sel.ProcessType
            UNION ALL SELECT 'sel.StageKind',         COUNT(*) FROM sel.StageKind
            UNION ALL SELECT 'sel.WizardStep',        COUNT(*) FROM sel.WizardStep
            UNION ALL SELECT 'sel.ValidationRule',    COUNT(*) FROM sel.ValidationRule
            UNION ALL SELECT 'sel.ReadinessLevel',    COUNT(*) FROM sel.ReadinessLevel
            UNION ALL SELECT 'sec.Role',              COUNT(*) FROM sec.Role
            UNION ALL SELECT 'sec.RoleScreenGrant',   COUNT(*) FROM sec.RoleScreenGrant
            """).ToList();

        counts.Should().AllSatisfy(c => c.Rows.Should().BeGreaterThan(0,
            $"{c.TableName} is seeded by the migration"));
    }

    [DatabaseFact]
    public void No_seeded_list_has_duplicate_codes()
    {
        using var db = Database.Open();

        // A MERGE keyed on the wrong column inserts a second copy on the second run.
        db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM (SELECT DomainId, ValueCode FROM cfg.DomainValue " +
            "GROUP BY DomainId, ValueCode HAVING COUNT(*) > 1) d")
            .Should().Be(0);

        db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM (SELECT ScreenCode FROM cfg.Screen GROUP BY ScreenCode HAVING COUNT(*) > 1) s")
            .Should().Be(0);

        db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM (SELECT SettingKey FROM cfg.Setting GROUP BY SettingKey HAVING COUNT(*) > 1) s")
            .Should().Be(0);

        db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM (SELECT MessageKey FROM cfg.Message GROUP BY MessageKey HAVING COUNT(*) > 1) m")
            .Should().Be(0);
    }

    [DatabaseFact]
    public void Every_message_the_application_looks_up_exists()
    {
        using var db = Database.Open();

        // A missing message is a blank space where a sentence should be.
        var keys = new[]
        {
            "READONLY_REFUSAL", "CLOSED_CYCLE", "SOURCE_UNMAPPED", "SAMPLED_FIGURES",
            "SHARE_UNDER_ONE", "SHARE_OVER_NINETYNINE", "SENSITIVE_FILTER",
            "LADDER_HELD", "LADDER_SHORT", "LADDER_DISQUALIFIED", "LADDER_NO_THRESHOLD",
        };

        foreach (var key in keys)
        {
            var text = db.ExecuteScalar<string?>(
                "SELECT cfg.fn_Message(@key)", new { key });

            text.Should().NotBeNullOrWhiteSpace($"cfg.Message is missing {key}");
        }
    }

    [DatabaseFact]
    public void Every_configuration_stamp_is_over_content_not_over_a_row_count()
    {
        using var db = Database.Open();

        var first = db.QuerySingle<(string Stamp, long ContentLength)>("EXEC cfg.usp_Config_Stamp");
        first.Stamp.Should().NotBeNullOrWhiteSpace();
        first.ContentLength.Should().BeGreaterThan(0);

        using var transaction = db.BeginTransaction();

        // Rename one value. The row count has not changed at all; the stamp must.
        db.Execute(
            "UPDATE TOP (1) cfg.DomainValue SET Name = Name + N' (renamed by a test)'",
            transaction: transaction);

        var second = db.QuerySingle<(string Stamp, long ContentLength)>(
            "EXEC cfg.usp_Config_Stamp", transaction: transaction);

        second.Stamp.Should().NotBe(first.Stamp,
            "a cache keyed on a row count would serve the old wording forever");

        transaction.Rollback();
    }

    [DatabaseFact]
    public void The_health_check_is_a_procedure_like_everything_else()
    {
        using var db = Database.Open();

        var exists = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM sys.procedures p JOIN sys.schemas s ON s.schema_id = p.schema_id " +
            "WHERE s.name = 'cfg' AND p.name = 'usp_Health_Check'");

        exists.Should().Be(1, "there is no SQL text in the application, not even a SELECT 1");
    }
}
