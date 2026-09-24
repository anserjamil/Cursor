namespace Maseera.Core.Dtos;

public sealed record UserContextRow(
    int AppUserId, string LoginName, string DisplayName, string? PersonnelNo, string? Email,
    DateOnly? AuthorizationEndsOn, bool IsBootstrap, bool IsActive,
    string? RoleCode, string? RoleName, bool IsReadOnly, int OrgScopeCount, bool HasRlsBypass,
    string? AuthorizationNote, DateOnly AsOf);

public sealed record RoleRow(
    int RoleId, string RoleCode, string Name, string? Description,
    bool IsReadOnly, int SortOrder, bool IsActive, int UserCount);

public sealed record PolicyScreenRow(
    int ScreenId, string ScreenCode, string Name, string AreaName, bool IsInMenu,
    int SortOrder, string? GroupCaption, int? GroupSort);

/// <summary>
/// One cell of the grant matrix. GrantValue null is "no rule" — a visible third state,
/// not an empty cell.
/// </summary>
public sealed record PolicyGrantRow(int RoleId, int ScreenId, short? GrantValue);

public sealed record AppUserRow(
    int AppUserId, string LoginName, string DisplayName, string? PersonnelNo, string? Email,
    DateOnly? AuthorizationEndsOn, bool IsBootstrap, bool IsActive,
    string? AddedByLogin, DateTime AddedOnUtc, string? RoleCode, string? RoleName,
    int OverrideCount, int OrgGrantCount, int OrgScopeCount,
    string? AuthorizationNote, string? AuthorizationRole);

public sealed record UserOverrideRow(
    int AppUserId, string LoginName, int ScreenId, string ScreenCode, string ScreenName,
    short GrantValue, string? Note, string? GrantedByLogin, DateTime GrantedOnUtc);

/// <summary>
/// What a screen resolves to for one login, and which of the six precedence rules
/// decided it. The screen renders the rule, not just the outcome.
/// </summary>
public sealed record ScreenAccessExplainRow(
    int ScreenId, string ScreenCode, string Name, string AreaName, string? GroupCaption,
    short GrantValue, string RuleCode);

public sealed record OrgTreeRow(
    int OrgNodeId, string OrgCode, string Name, string? ParentOrgCode, byte OrgLevel,
    bool IsActive, int HeadCount, bool IsGranted, bool? IsGrantedCompare);

public sealed record RlsCompareRow(
    string WhichLogin, string Login, int Units, int People, int InPools);

public sealed record DirectoryPersonRow(
    string LoginName, string DisplayName, string? Email, string? PersonnelNo, string? RoleName);

/// <summary>
/// The six rules of the precedence, in the order the engine applies them. These are the
/// codes sec.fn_ScreenAccessRule returns; the wording lives beside them so the access
/// screen can render the list without inventing its own.
/// </summary>
public static class AccessRules
{
    public const string Bootstrap     = "BOOTSTRAP";
    public const string NotRegistered = "NOT_REGISTERED";
    public const string Expired       = "EXPIRED";
    public const string UserOverride  = "USER_OVERRIDE";
    public const string RolePolicy    = "ROLE_POLICY";
    public const string NoRule        = "NO_RULE";

    /// <summary>The precedence as it is applied, in order, for the numbered list.</summary>
    public static readonly IReadOnlyList<(string Code, string Title, string Explanation)> Ordered =
    [
        (Bootstrap,     "Bootstrap",
            "The seeded administrator, so a fresh database is always reachable."),
        (NotRegistered, "Not registered",
            "The login has no user record, so it is denied before anything else is considered."),
        (Expired,       "Expired",
            "The login's authorization ended before the as-of date, so it is denied."),
        (UserOverride,  "User override",
            "A grant set against this person replaces the role rule outright, and may widen or narrow it."),
        (RolePolicy,    "Role policy",
            "The grant their role carries for this screen."),
        (NoRule,        "No rule",
            "Nothing grants this screen to this login, so it is denied."),
    ];
}

/// <summary>Grant values, as the database stores them.</summary>
public static class Grants
{
    public const short Deny = 0;
    public const short Read = 1;
    public const short Write = 2;

    public static string Word(short? value) => value switch
    {
        Write => "Read and write",
        Read => "Read",
        Deny => "Denied",
        _ => "No rule",
    };

    /// <summary>
    /// Read-only, read-and-write and no-grant are separated by fill weight as well as
    /// tint, so the matrix survives greyscale.
    /// </summary>
    public static string CssClass(short? value) => value switch
    {
        Write => "ms-grant ms-grant--write",
        Read => "ms-grant ms-grant--read",
        Deny => "ms-grant ms-grant--deny",
        _ => "ms-grant ms-grant--none",
    };
}
