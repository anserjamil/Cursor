using FluentAssertions;
using Maseera.Core.Presentation;

namespace Maseera.Tests.Unit;

/// <summary>
/// Part 12.4: never print a percentage that contradicts its count.
///
/// These are the cases from the build prompt, and the ones a reader actually notices:
/// the 1-in-12,000 that must not read as 0%, and the 11,999-in-12,000 that must not read
/// as 100% while one person is plainly missing.
/// </summary>
public class ShareTextTests
{
    [Fact]
    public void Nothing_to_divide_by_is_not_zero_percent()
    {
        // 0 of 0 is not an answer. Printing "0%" would claim one.
        Share.Text(0, 0).Should().Be("—");
        Share.Text(5, 0).Should().Be("—");
        Share.Text(0, -1).Should().Be("—");
    }

    [Fact]
    public void A_genuine_zero_reads_as_zero()
    {
        Share.Text(0, 300).Should().Be("0%");
    }

    [Fact]
    public void A_genuine_whole_reads_as_a_hundred()
    {
        Share.Text(300, 300).Should().Be("100%");
        Share.Text(301, 300).Should().Be("100%");
    }

    [Fact]
    public void One_in_twelve_thousand_is_not_zero_percent()
    {
        // 0.0083% rounds to nothing. Somebody is in that count and the sentence says so.
        Share.Text(1, 12_000).Should().Be("under 1%");
    }

    [Fact]
    public void All_but_one_of_twelve_thousand_is_not_a_hundred_percent()
    {
        Share.Text(11_999, 12_000).Should().Be("over 99%");
    }

    [Fact]
    public void The_two_sentences_come_from_configuration()
    {
        // An administrator rewords them in cfg.Message; the helper never hardcodes them.
        Share.Text(1, 12_000, "fewer than one in a hundred", "all but a handful")
            .Should().Be("fewer than one in a hundred");
        Share.Text(11_999, 12_000, "fewer than one in a hundred", "all but a handful")
            .Should().Be("all but a handful");
    }

    [Theory]
    [InlineData(41, 300, "14%")]
    [InlineData(1, 2, "50%")]
    [InlineData(1, 3, "33%")]
    [InlineData(2, 3, "67%")]
    [InlineData(374, 624, "60%")]
    public void An_ordinary_share_is_rounded_to_a_whole_number(long count, long total, string expected)
    {
        Share.Text(count, total).Should().Be(expected);
    }

    [Fact]
    public void A_half_rounds_away_from_zero_so_two_equal_shares_read_alike()
    {
        // 1 of 8 is 12.5%. Banker's rounding would make it 12% and 3 of 8 (37.5%) 38%,
        // which reads as an inconsistency to anyone adding them up.
        Share.Text(1, 8).Should().Be("13%");
        Share.Text(3, 8).Should().Be("38%");
    }

    [Fact]
    public void A_negative_count_is_treated_as_none()
    {
        Share.Text(-5, 300).Should().Be("0%");
    }

    [Fact]
    public void The_attainment_row_reads_as_the_prototype_wrote_it()
    {
        Share.CountAndShare(41, 300).Should().Be("41 of 300 · 14%");
        Share.CountAndShare(1, 12_000).Should().Be("1 of 12,000 · under 1%");
    }

    [Fact]
    public void A_bar_is_not_rounded_so_it_cannot_disagree_with_its_label()
    {
        // The label says 14%; the bar is drawn at 13.67%. Rounding the bar too would put
        // the fill on the wrong side of a tick that sits at 14.
        Share.Fraction(41, 300).Should().BeApproximately(13.6666, 0.001);
        Share.Fraction(0, 0).Should().Be(0d);
        Share.Fraction(400, 300).Should().Be(100d);
        Share.Fraction(-1, 300).Should().Be(0d);
    }
}
