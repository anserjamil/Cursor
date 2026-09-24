using Dapper;
using FluentAssertions;

namespace Maseera.Tests.Sql;

/// <summary>
/// The two promises the product cannot break: a viewer sees only their organisations,
/// and a read-only role writes nothing no matter what a grant says.
/// </summary>
public class SecurityTests
{
    [DatabaseFact]
    public void Two_viewers_of_the_same_cycle_see_different_people_and_both_are_right()
    {
        using var db = Database.Open();

        var cycleId = db.ExecuteScalar<int?>("SELECT MAX(CycleId) FROM sel.Cycle");
        if (cycleId is null) return;   // nothing opened on this instance

        var wide = db.ExecuteScalar<int>(
            """
            SELECT COUNT(*) FROM sel.CycleCandidate cc
            JOIN sec.fn_UserOrgScope(@login) s ON s.OrgCode = cc.OrgCode
            WHERE cc.CycleId = @cycleId
            """, new { login = Database.Hrbp, cycleId });

        var narrow = db.ExecuteScalar<int>(
            """
            SELECT COUNT(*) FROM sel.CycleCandidate cc
            JOIN sec.fn_UserOrgScope(@login) s ON s.OrgCode = cc.OrgCode
            WHERE cc.CycleId = @cycleId
            """, new { login = Database.Svp, cycleId });

        // The narrower grant must be a subset, never merely a different number.
        narrow.Should().BeLessThanOrEqualTo(wide);

        var onlyTheNarrowOneSees = db.ExecuteScalar<int>(
            """
            SELECT COUNT(*) FROM sel.CycleCandidate cc
            JOIN sec.fn_UserOrgScope(@narrow) n ON n.OrgCode = cc.OrgCode
            WHERE cc.CycleId = @cycleId
              AND NOT EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@wide) w WHERE w.OrgCode = cc.OrgCode)
            """, new { narrow = Database.Svp, wide = Database.Hrbp, cycleId });

        onlyTheNarrowOneSees.Should().Be(0,
            "a grant on one division is contained by a grant on the company");
    }

    [DatabaseFact]
    public void A_login_with_no_user_record_is_scoped_to_nothing()
    {
        using var db = Database.Open();

        var units = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM sec.fn_UserOrgScope(@login)",
            new { login = "somebody.who.does.not.exist" });

        units.Should().Be(0, "rule 2 denies a login with no user record before anything else");
    }

    [DatabaseFact]
    public void A_grant_carries_down_the_tree_and_no_further()
    {
        using var db = Database.Open();

        var granted = db.Query<string>(
            "SELECT OrgCode FROM sec.UserOrgGrant g JOIN sec.AppUser u ON u.AppUserId = g.AppUserId " +
            "WHERE u.LoginName = @login", new { login = Database.Svp }).ToList();

        if (granted.Count == 0) return;

        foreach (var root in granted)
        {
            // Everything beneath a granted node is in scope.
            var beneathButOutOfScope = db.ExecuteScalar<int>(
                """
                SELECT COUNT(*)
                FROM sel.OrgAncestor a
                WHERE a.AncestorOrgCode = @root
                  AND NOT EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@login) s WHERE s.OrgCode = a.OrgCode)
                """, new { root, login = Database.Svp });

            beneathButOutOfScope.Should().Be(0,
                $"everything under {root} is granted with it");
        }
    }

    [DatabaseFact]
    public void The_auditor_reads_every_screen_and_writes_to_none_of_them()
    {
        using var db = Database.Open();

        var readable = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM cfg.Screen s WHERE sec.fn_ScreenAccess(@login, s.ScreenCode) >= 1",
            new { login = Database.Auditor });

        var writable = db.ExecuteScalar<int>(
            "SELECT COUNT(*) FROM cfg.Screen s WHERE sec.fn_ScreenAccess(@login, s.ScreenCode) >= 2",
            new { login = Database.Auditor });

        readable.Should().BeGreaterThan(0, "the auditor is granted read everywhere");
        writable.Should().Be(0, "the read-only flag on the role is what stops any of it becoming write");
    }

    [DatabaseFact]
    public void No_grant_can_give_a_read_only_role_write()
    {
        using var db = Database.Open();
        using var transaction = db.BeginTransaction();

        var screenId = db.ExecuteScalar<int>(
            "SELECT MIN(ScreenId) FROM cfg.Screen", transaction: transaction);

        var auditorId = db.ExecuteScalar<int>(
            "SELECT AppUserId FROM sec.AppUser WHERE LoginName = @login",
            new { login = Database.Auditor }, transaction);

        // Set the most permissive grant there is, directly against the person — rule 4,
        // the one that overrides the role policy outright.
        db.Execute(
            """
            MERGE sec.UserScreenGrant AS t
            USING (SELECT @auditorId AS AppUserId, @screenId AS ScreenId) AS s
               ON t.AppUserId = s.AppUserId AND t.ScreenId = s.ScreenId
            WHEN MATCHED THEN UPDATE SET GrantValue = 2
            WHEN NOT MATCHED THEN INSERT (AppUserId, ScreenId, GrantValue, Note)
                 VALUES (s.AppUserId, s.ScreenId, 2, N'A test trying to widen a read-only role.');
            """, new { auditorId, screenId }, transaction);

        var grant = db.ExecuteScalar<short?>(
            "SELECT sec.fn_ScreenAccess(@login, (SELECT ScreenCode FROM cfg.Screen WHERE ScreenId = @screenId))",
            new { login = Database.Auditor, screenId }, transaction);

        grant.Should().BeLessThanOrEqualTo((short)1,
            "AUDITOR carries IsReadOnly, and no grant can give it write");

        transaction.Rollback();
    }

    [DatabaseFact]
    public void Each_screen_resolves_through_exactly_one_of_the_six_rules()
    {
        using var db = Database.Open();

        var logins = new[] { Database.Administrator, Database.Hrbp, Database.Svp, Database.Auditor, "nobody.at.all" };
        var known = new[] { "BOOTSTRAP", "NOT_REGISTERED", "EXPIRED", "USER_OVERRIDE", "ROLE_POLICY", "NO_RULE" };

        // The rule function takes the as-of date because the whole product reads against
        // one: an authorization that ends tomorrow is not expired today, and the answer
        // has to be the same one the screen will give.
        var asOf = db.ExecuteScalar<DateTime>("SELECT CAST(SYSUTCDATETIME() AS date)");

        foreach (var login in logins)
        {
            var rules = db.Query<string>(
                "SELECT DISTINCT sec.fn_ScreenAccessRule(@login, s.ScreenCode, @asOf) FROM cfg.Screen s",
                new { login, asOf }).ToList();

            rules.Should().NotBeEmpty();
            rules.Should().OnlyContain(r => known.Contains(r),
                $"every outcome for {login} is nameable as one of the six rules");
        }
    }

    [DatabaseFact]
    public void An_expired_authorization_denies_before_the_role_is_consulted()
    {
        using var db = Database.Open();
        using var transaction = db.BeginTransaction();

        var screenCode = db.ExecuteScalar<string>(
            "SELECT TOP (1) ScreenCode FROM cfg.Screen ORDER BY ScreenId", transaction: transaction)!;

        var before = db.ExecuteScalar<short?>(
            "SELECT sec.fn_ScreenAccess(@login, @screenCode)",
            new { login = Database.Hrbp, screenCode }, transaction);

        before.Should().BeGreaterThan((short)0, "the business partner starts with access");

        db.Execute(
            "UPDATE sec.AppUser SET AuthorizationEndsOn = DATEADD(DAY, -1, CAST(SYSUTCDATETIME() AS date)) " +
            "WHERE LoginName = @login",
            new { login = Database.Hrbp }, transaction);

        var after = db.ExecuteScalar<short?>(
            "SELECT sec.fn_ScreenAccess(@login, @screenCode)",
            new { login = Database.Hrbp, screenCode }, transaction);

        after.Should().Be((short)0, "rule 3 denies before rule 5 is reached");

        var rule = db.ExecuteScalar<string>(
            "SELECT sec.fn_ScreenAccessRule(@login, @screenCode, CAST(SYSUTCDATETIME() AS date))",
            new { login = Database.Hrbp, screenCode }, transaction);

        rule.Should().Be("EXPIRED", "and the screen can say which rule it was");

        transaction.Rollback();
    }
}
