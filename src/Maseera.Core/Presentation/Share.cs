namespace Maseera.Core.Presentation;

/// <summary>
/// The one place a share is turned into words.
///
/// Part 12.4: never print a percentage that contradicts its count. A non-zero count that
/// rounds to 0% reads as "under 1%"; a count short of the total that rounds to 100% reads
/// as "over 99%". Five call sites would be five bugs, so every share in the application
/// comes through here — and a test scans the views to make sure none slips past.
///
/// The two sentences are configuration, not literals: the caller passes the text it read
/// from cfg.Message, which is why they are parameters and not constants.
/// </summary>
public static class Share
{
    public const string DefaultUnderOneText = "under 1%";
    public const string DefaultOverNinetyNineText = "over 99%";

    /// <summary>
    /// A count against a total, as the user should read it.
    /// </summary>
    /// <param name="count">How many. Negative counts are treated as zero.</param>
    /// <param name="total">Out of how many. Zero or negative gives an em dash.</param>
    /// <param name="underOneText">The wording for a non-zero count below one percent.</param>
    /// <param name="overNinetyNineText">The wording for a count below the total that rounds to a hundred.</param>
    public static string Text(
        long count,
        long total,
        string? underOneText = null,
        string? overNinetyNineText = null)
    {
        // Nothing to divide by is not zero percent; it is no answer at all.
        if (total <= 0) return "—";

        if (count <= 0) return "0%";
        if (count >= total) return "100%";

        var pct = 100d * count / total;
        var rounded = Math.Round(pct, MidpointRounding.AwayFromZero);

        // A real person who rounds away is the bug this exists to prevent.
        if (rounded <= 0) return underOneText ?? DefaultUnderOneText;
        if (rounded >= 100) return overNinetyNineText ?? DefaultOverNinetyNineText;

        return rounded.ToString("0") + "%";
    }

    /// <summary>
    /// The same share as a number, for a bar's width. It is clamped to 0..100 but is NOT
    /// rounded, so a bar and its label can never disagree about which side of a whole
    /// number they are on.
    /// </summary>
    public static double Fraction(long count, long total)
    {
        if (total <= 0) return 0d;
        if (count <= 0) return 0d;
        if (count >= total) return 100d;
        return 100d * count / total;
    }

    /// <summary>
    /// The prototype's attainment row: "41 of 300 · 14%".
    /// </summary>
    public static string CountAndShare(
        long count,
        long total,
        string? underOneText = null,
        string? overNinetyNineText = null)
        => $"{count:N0} of {total:N0} · {Text(count, total, underOneText, overNinetyNineText)}";
}
