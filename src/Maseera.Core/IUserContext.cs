namespace Maseera.Core;

/// <summary>
/// Who is asking, and as of when. Resolved once per request from sec.AppUser and
/// sec.UserRole, and passed to every procedure by the runner so a developer cannot
/// forget it.
/// </summary>
public interface IUserContext
{
    /// <summary>The sAMAccountName, matched to sec.AppUser.LoginName.</summary>
    string LoginName { get; }

    string DisplayName { get; }

    /// <summary>The role code, for display only. No decision is ever taken from it.</summary>
    string? RoleCode { get; }

    string? RoleName { get; }

    /// <summary>
    /// True when the login's role carries the read-only flag. Read and write are separate
    /// grants; this is the flag no grant can override.
    /// </summary>
    bool IsReadOnly { get; }

    /// <summary>
    /// The date all date logic reads against: today, unless configuration or an
    /// administrator's ?asOf= says otherwise.
    /// </summary>
    DateOnly AsOf { get; }

    /// <summary>
    /// Ignores stage and cycle windows so every stage accepts decisions. Administrator
    /// only, and every decision taken in it is stamped TEST.
    /// </summary>
    bool TestMode { get; }

    /// <summary>How many organisations this login may read. Shown in the scope pill.</summary>
    int OrgScopeCount { get; }

    /// <summary>True when the login has no sec.AppUser row at all.</summary>
    bool IsRegistered { get; }

    /// <summary>"Authorization ended" / "Ends within four months", or null.</summary>
    string? AuthorizationNote { get; }

    string? AuthorizationRole { get; }

    /// <summary>True when the request is running as somebody else through the development switcher.</summary>
    bool IsImpersonating { get; }
}
