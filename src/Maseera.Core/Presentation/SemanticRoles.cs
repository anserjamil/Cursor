namespace Maseera.Core.Presentation;

/// <summary>
/// cfg.DomainValue.SemanticRole names a meaning; this turns it into a stylesheet class.
///
/// The database never carries a hex colour and neither does a view. Colour means one
/// thing here: success, warning and danger are states, never decoration. Anything this
/// does not recognise falls back to the neutral class rather than to nothing, so an
/// administrator who invents a new role gets a readable chip instead of an unstyled one.
/// </summary>
public static class SemanticRoles
{
    public const string Neutral = "ms-state--neutral";

    private static readonly Dictionary<string, string> Map = new(StringComparer.OrdinalIgnoreCase)
    {
        ["neutral"]  = Neutral,
        ["positive"] = "ms-state--positive",
        ["warning"]  = "ms-state--warning",
        ["danger"]   = "ms-state--danger",
        ["info"]     = "ms-state--info",
        ["muted"]    = "ms-state--muted",
        // The outcome pill is solid ink, and is the only pill that is.
        ["outcome"]  = "ms-state--outcome",
    };

    /// <summary>The chip or pill class for a semantic role.</summary>
    public static string CssClass(string? semanticRole)
        => semanticRole is not null && Map.TryGetValue(semanticRole, out var css) ? css : Neutral;

    /// <summary>
    /// The class for a tinted row. Recessive text on a tinted row needs a darker tier
    /// than the same text on white, so the row carries its own modifier and the
    /// stylesheet resolves the tier against the surface rather than hardcoding it.
    /// </summary>
    public static string RowCssClass(string? semanticRole)
        => semanticRole is null ? string.Empty : "ms-row--" + semanticRole.ToLowerInvariant();

    /// <summary>Every role the stylesheet knows, for the reference-data editor's picker.</summary>
    public static IReadOnlyCollection<string> Known => Map.Keys;
}
