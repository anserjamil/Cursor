namespace Maseera.Data;

/// <summary>
/// The Maseera section of appsettings. Nothing here is a business rule — those live in
/// cfg.Setting. These are the knobs that have to exist before the database can be read.
/// </summary>
public sealed class MaseeraOptions
{
    public const string SectionName = "Maseera";

    /// <summary>
    /// Run the whole application as if it were this day. Null means today. The same
    /// override exists in cfg.Setting so the database agrees with the application.
    /// </summary>
    public DateOnly? AsOfOverride { get; set; }

    /// <summary>
    /// The connection string carries Command Timeout=0, which means no timeout at the
    /// connection level. Every command gets this instead, so a runaway preview cannot
    /// hold a request open for ever.
    /// </summary>
    public int CommandTimeoutSeconds { get; set; } = 120;

    /// <summary>The schema the customer's operational tables sit in.</summary>
    public string RosterSchema { get; set; } = "dbo";

    /// <summary>
    /// Whether the development-only "Sign in as" switcher is reachable. It must be
    /// impossible to reach in any other environment, so Program.cs also gates it on the
    /// hosting environment and this flag is only ever the second lock.
    /// </summary>
    public bool AllowImpersonation { get; set; }

    /// <summary>The login used when Windows authentication is not available (development only).</summary>
    public string? DevelopmentLogin { get; set; }
}
