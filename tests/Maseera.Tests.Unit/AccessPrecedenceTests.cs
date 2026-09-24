using FluentAssertions;
using Maseera.Core.Dtos;

namespace Maseera.Tests.Unit;

/// <summary>
/// The six rules, and the words the access screen renders.
///
/// The precedence itself is decided in SQL (sec.fn_ScreenAccessAsOf); these guard the
/// half the application owns — that the list is complete, in order, and that no rule code
/// the database can return is one the screen cannot name.
/// </summary>
public class AccessPrecedenceTests
{
    [Fact]
    public void There_are_six_rules_and_they_are_in_the_order_the_engine_applies_them()
    {
        AccessRules.Ordered.Select(r => r.Code).Should().Equal(
            AccessRules.Bootstrap,
            AccessRules.NotRegistered,
            AccessRules.Expired,
            AccessRules.UserOverride,
            AccessRules.RolePolicy,
            AccessRules.NoRule);
    }

    [Fact]
    public void Every_rule_has_a_title_and_an_explanation()
    {
        // The screen renders both. A rule with an empty explanation is a denial nobody
        // can act on.
        foreach (var (code, title, explanation) in AccessRules.Ordered)
        {
            code.Should().NotBeNullOrWhiteSpace();
            title.Should().NotBeNullOrWhiteSpace();
            explanation.Should().NotBeNullOrWhiteSpace();
            explanation.Should().EndWith(".", because: "the explanations are sentences");
        }
    }

    [Fact]
    public void A_rule_code_is_listed_once()
    {
        AccessRules.Ordered.Select(r => r.Code).Should().OnlyHaveUniqueItems();
    }

    [Theory]
    [InlineData((short)2, "Read and write")]
    [InlineData((short)1, "Read")]
    [InlineData((short)0, "Denied")]
    [InlineData(null, "No rule")]
    public void A_grant_has_four_states_and_no_rule_is_one_of_them(short? grant, string expected)
    {
        // "No rule" is a visible third state, not an empty cell. A blank in the matrix
        // reads as "nobody has decided", which is exactly what it means.
        Grants.Word(grant).Should().Be(expected);
    }

    [Fact]
    public void Each_grant_state_has_its_own_fill_so_the_matrix_survives_greyscale()
    {
        var classes = new[] { Grants.Write, Grants.Read, Grants.Deny }
            .Select(g => Grants.CssClass(g))
            .Append(Grants.CssClass(null))
            .ToList();

        classes.Should().OnlyHaveUniqueItems();
        classes.Should().AllSatisfy(c => c.Should().StartWith("ms-grant"));
    }

    [Fact]
    public void An_unexpected_grant_value_reads_as_no_rule_rather_than_as_permission()
    {
        // Fail closed. A value the application has never seen is not an entitlement.
        Grants.Word(7).Should().Be("No rule");
        Grants.CssClass(7).Should().Be(Grants.CssClass(null));
    }

    [Fact]
    public void The_grant_values_are_the_ones_the_database_stores()
    {
        Grants.Deny.Should().Be(0);
        Grants.Read.Should().Be(1);
        Grants.Write.Should().Be(2);
    }
}

/// <summary>
/// A screen row knows what the viewer may do with it, and the navigation and the guard
/// both read those two properties.
/// </summary>
public class ScreenGrantTests
{
    private static ScreenRow Screen(short? grant) => new(
        1, "/Selection/Cycles/", "Cycles", "Selection", "Cycles", "Index",
        null, null, true, 10, true, grant);

    [Fact]
    public void Write_implies_read()
    {
        Screen(2).CanRead.Should().BeTrue();
        Screen(2).CanWrite.Should().BeTrue();
    }

    [Fact]
    public void Read_does_not_imply_write()
    {
        Screen(1).CanRead.Should().BeTrue();
        Screen(1).CanWrite.Should().BeFalse();
    }

    [Fact]
    public void An_explicit_deny_and_no_rule_at_all_both_allow_nothing()
    {
        Screen(0).CanRead.Should().BeFalse();
        Screen(0).CanWrite.Should().BeFalse();
        Screen(null).CanRead.Should().BeFalse();
        Screen(null).CanWrite.Should().BeFalse();
    }
}

/// <summary>
/// The plan states are strings on purpose.
///
/// A C# enum mirroring a domain is the failure mode the whole design exists to avoid:
/// cfg.DomainValue owns the list, and an administrator adding a state must not need a
/// recompile. These constants are a spelling aid for the three the application itself
/// reasons about, not a closed set.
/// </summary>
public class IdpPlanStateTests
{
    [Fact]
    public void The_states_are_strings_not_an_enum()
    {
        typeof(IdpPlanStates).IsEnum.Should().BeFalse();
        typeof(IdpPlanStates).GetFields()
            .Where(f => f.IsLiteral)
            .Should().AllSatisfy(f => f.FieldType.Should().Be<string>());
    }

    [Fact]
    public void The_named_states_are_distinct()
    {
        var values = typeof(IdpPlanStates).GetFields()
            .Where(f => f.IsLiteral)
            .Select(f => (string)f.GetRawConstantValue()!)
            .ToList();

        values.Should().NotBeEmpty();
        values.Should().OnlyHaveUniqueItems();
    }
}
