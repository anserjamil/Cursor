using Maseera.Core;

namespace Maseera.Web.Security;

/// <summary>
/// The request's user context. Populated once, by <see cref="UserContextMiddleware"/>,
/// before authorization runs — so the ScreenAccess handler, every repository and every
/// view are all looking at the same person and the same as-of date.
/// </summary>
public sealed class UserContext : IUserContext
{
    public string LoginName { get; private set; } = string.Empty;
    public string DisplayName { get; private set; } = string.Empty;
    public string? RoleCode { get; private set; }
    public string? RoleName { get; private set; }
    public bool IsReadOnly { get; private set; }
    public DateOnly AsOf { get; private set; } = DateOnly.FromDateTime(DateTime.UtcNow);
    public bool TestMode { get; private set; }
    public int OrgScopeCount { get; private set; }
    public bool IsRegistered { get; private set; }
    public string? AuthorizationNote { get; private set; }
    public string? AuthorizationRole { get; private set; }
    public bool IsImpersonating { get; private set; }

    /// <summary>True when this login sees every organisation, explicitly and auditably.</summary>
    public bool HasRlsBypass { get; private set; }

    /// <summary>The login Windows actually authenticated, before any development switch.</summary>
    public string? RealLoginName { get; private set; }

    internal void Apply(
        string loginName, string displayName, string? roleCode, string? roleName,
        bool isReadOnly, DateOnly asOf, bool testMode, int orgScopeCount, bool isRegistered,
        string? authorizationNote, string? authorizationRole,
        bool hasRlsBypass, string? realLoginName, bool isImpersonating)
    {
        LoginName = loginName;
        DisplayName = displayName;
        RoleCode = roleCode;
        RoleName = roleName;
        IsReadOnly = isReadOnly;
        AsOf = asOf;
        TestMode = testMode;
        OrgScopeCount = orgScopeCount;
        IsRegistered = isRegistered;
        AuthorizationNote = authorizationNote;
        AuthorizationRole = authorizationRole;
        HasRlsBypass = hasRlsBypass;
        RealLoginName = realLoginName;
        IsImpersonating = isImpersonating;
    }
}
