namespace Maseera.Core.Presentation;

/// <summary>
/// Dates read against the as-of date, never against today.
///
/// The application can be run as if it were any day (a configuration override, or
/// ?asOf= for an administrator), and a date that quietly compared itself to DateTime.Today
/// would make the screen disagree with the database about which stage is open.
/// </summary>
public static class AsOf
{
    /// <summary>A date as the interface writes it.</summary>
    public static string Date(DateOnly? value) => value?.ToString("d MMM yyyy") ?? "—";

    public static string Date(DateTime? value)
        => value is null ? "—" : DateOnly.FromDateTime(value.Value).ToString("d MMM yyyy");

    /// <summary>A window, as one phrase: "3 Feb 2026 – 28 Feb 2026".</summary>
    public static string Window(DateOnly? from, DateOnly? to)
    {
        if (from is null && to is null) return "No window set";
        if (from is null) return "Until " + Date(to);
        if (to is null) return "From " + Date(from);
        return $"{Date(from)} – {Date(to)}";
    }

    /// <summary>
    /// How a date sits against the as-of date, in words. Whole days only: the product
    /// works in stage windows, not in hours.
    /// </summary>
    public static string Relative(DateOnly? value, DateOnly asOfDate)
    {
        if (value is null) return "—";

        var days = value.Value.DayNumber - asOfDate.DayNumber;
        return days switch
        {
            0 => "today",
            1 => "tomorrow",
            -1 => "yesterday",
            > 1 and < 14 => $"in {days} days",
            < -1 and > -14 => $"{-days} days ago",
            > 0 => $"in {DaysAsSpan(days)}",
            _ => $"{DaysAsSpan(-days)} ago",
        };
    }

    /// <summary>Days left in a window, for the IDP countdown. Negative means overdue.</summary>
    public static int? DaysLeft(DateOnly? until, DateOnly asOfDate)
        => until is null ? null : until.Value.DayNumber - asOfDate.DayNumber;

    /// <summary>
    /// Whether a date has passed. An open plan past its target reads as overdue, and
    /// this is the one place that decides what "past" means.
    /// </summary>
    public static bool IsPast(DateOnly? value, DateOnly asOfDate)
        => value is not null && value.Value < asOfDate;

    private static string DaysAsSpan(int days)
    {
        if (days < 60) return $"{days / 7} weeks";
        if (days < 730) return $"{days / 30} months";
        return $"{days / 365} years";
    }
}
