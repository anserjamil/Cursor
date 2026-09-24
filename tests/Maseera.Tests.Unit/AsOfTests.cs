using FluentAssertions;
using Maseera.Core.Presentation;

namespace Maseera.Tests.Unit;

/// <summary>
/// Every date is read against the as-of date, never against today. The application can
/// be run as if it were any day; a comparison against DateTime.Today would make the
/// screen disagree with the database about which stage is open.
/// </summary>
public class AsOfTests
{
    private static readonly DateOnly AsOfDate = new(2026, 3, 1);

    [Fact]
    public void A_date_with_no_value_is_a_dash_not_a_zero_date()
    {
        AsOf.Date((DateOnly?)null).Should().Be("—");
        AsOf.Date((DateTime?)null).Should().Be("—");
        AsOf.Relative(null, AsOfDate).Should().Be("—");
        AsOf.DaysLeft(null, AsOfDate).Should().BeNull();
    }

    [Fact]
    public void A_window_says_what_it_actually_knows()
    {
        AsOf.Window(null, null).Should().Be("No window set");
        AsOf.Window(new DateOnly(2026, 2, 3), null).Should().Be("From 3 Feb 2026");
        AsOf.Window(null, new DateOnly(2026, 2, 28)).Should().Be("Until 28 Feb 2026");
        AsOf.Window(new DateOnly(2026, 2, 3), new DateOnly(2026, 2, 28))
            .Should().Be("3 Feb 2026 – 28 Feb 2026");
    }

    [Theory]
    [InlineData(2026, 3, 1, "today")]
    [InlineData(2026, 3, 2, "tomorrow")]
    [InlineData(2026, 2, 28, "yesterday")]
    [InlineData(2026, 3, 6, "in 5 days")]
    [InlineData(2026, 2, 24, "5 days ago")]
    public void A_nearby_date_is_read_in_days(int y, int m, int d, string expected)
    {
        AsOf.Relative(new DateOnly(y, m, d), AsOfDate).Should().Be(expected);
    }

    [Fact]
    public void A_distant_date_is_read_in_the_largest_unit_that_still_means_something()
    {
        AsOf.Relative(new DateOnly(2026, 4, 1), AsOfDate).Should().Be("in 4 weeks");
        AsOf.Relative(new DateOnly(2026, 9, 1), AsOfDate).Should().Be("in 6 months");
        AsOf.Relative(new DateOnly(2024, 3, 1), AsOfDate).Should().Be("2 years ago");
    }

    [Fact]
    public void Past_is_decided_against_the_as_of_date_and_nothing_else()
    {
        // Run as if it were 1 March 2026: a January date is past even if the machine's
        // clock says 2030, and a 2027 date is not past even if the clock says 2030.
        AsOf.IsPast(new DateOnly(2026, 1, 1), AsOfDate).Should().BeTrue();
        AsOf.IsPast(new DateOnly(2027, 1, 1), AsOfDate).Should().BeFalse();

        // The as-of date itself has not passed: a stage closing today is still open.
        AsOf.IsPast(AsOfDate, AsOfDate).Should().BeFalse();

        AsOf.IsPast(null, AsOfDate).Should().BeFalse();
    }

    [Fact]
    public void Days_left_is_negative_when_it_is_overdue()
    {
        AsOf.DaysLeft(new DateOnly(2026, 3, 11), AsOfDate).Should().Be(10);
        AsOf.DaysLeft(AsOfDate, AsOfDate).Should().Be(0);
        AsOf.DaysLeft(new DateOnly(2026, 2, 19), AsOfDate).Should().Be(-10);
    }
}

/// <summary>
/// A semantic role is a meaning, and the stylesheet decides what it looks like. The
/// database never carries a colour, and neither does a view.
/// </summary>
public class SemanticRoleTests
{
    [Theory]
    [InlineData("neutral",  "ms-state--neutral")]
    [InlineData("positive", "ms-state--positive")]
    [InlineData("warning",  "ms-state--warning")]
    [InlineData("danger",   "ms-state--danger")]
    [InlineData("info",     "ms-state--info")]
    [InlineData("muted",    "ms-state--muted")]
    [InlineData("outcome",  "ms-state--outcome")]
    public void Each_role_the_seed_data_uses_has_a_class(string role, string expected)
    {
        SemanticRoles.CssClass(role).Should().Be(expected);
    }

    [Fact]
    public void The_role_is_matched_whatever_case_it_was_written_in()
    {
        SemanticRoles.CssClass("POSITIVE").Should().Be("ms-state--positive");
        SemanticRoles.CssClass("Warning").Should().Be("ms-state--warning");
    }

    [Fact]
    public void A_role_nobody_has_styled_yet_still_reads_as_a_chip()
    {
        // An administrator inventing a role should get a readable neutral chip, never an
        // unstyled span.
        SemanticRoles.CssClass("brand-new").Should().Be(SemanticRoles.Neutral);
        SemanticRoles.CssClass(null).Should().Be(SemanticRoles.Neutral);
        SemanticRoles.CssClass("").Should().Be(SemanticRoles.Neutral);
    }

    [Fact]
    public void Every_role_the_picker_offers_is_one_the_stylesheet_knows()
    {
        // The reference-data editor lists SemanticRoles.Known. If one of those did not
        // resolve, an administrator could pick a role that renders as neutral.
        SemanticRoles.Known.Should().NotBeEmpty();
        foreach (var role in SemanticRoles.Known.Where(r => r != "neutral"))
            SemanticRoles.CssClass(role).Should().NotBe(SemanticRoles.Neutral,
                because: $"'{role}' is offered in the picker, so it must have its own class");
    }

    [Fact]
    public void A_tinted_row_carries_its_own_modifier()
    {
        // Recessive text on a tinted row needs a darker tier than on white; the row says
        // which surface it is so the stylesheet can resolve the tier.
        SemanticRoles.RowCssClass("Warning").Should().Be("ms-row--warning");
        SemanticRoles.RowCssClass(null).Should().BeEmpty();
    }
}
