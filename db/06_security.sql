/* =====================================================================================
   06_security.sql  —  who may see what, and who may change it
   -------------------------------------------------------------------------------------
   Two independent questions:

     * screen access — may this login read, or read and write, this screen?  Decided by
       sec.fn_ScreenAccess, which applies the shipped precedence in one place so no
       controller ever carries a role literal.
     * row-level security — which people's rows may this login see?  Decided by
       sec.fn_UserOrgScope, which every read joins, including the drilldown behind every
       count.  Two people looking at the same cycle legitimately see different people.

   Grant values: 2 = allow and write, 1 = allow and read, 0 = explicit deny, NULL = no rule.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 06_security =======================================================';
GO

IF OBJECT_ID('sec.Role') IS NULL
BEGIN
    CREATE TABLE sec.Role
    (
        RoleId   int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_Role PRIMARY KEY,
        RoleCode nvarchar(40)  NOT NULL CONSTRAINT UQ_sec_Role_Code UNIQUE,
        Name     nvarchar(120) NOT NULL,
        Description nvarchar(400) NULL,
        /* An auditor reads everything and changes nothing.  No grant can give it write. */
        IsReadOnly bit         NOT NULL CONSTRAINT DF_sec_Role_ReadOnly DEFAULT (0),
        SortOrder int          NOT NULL CONSTRAINT DF_sec_Role_Sort     DEFAULT (0),
        IsActive  bit          NOT NULL CONSTRAINT DF_sec_Role_Active   DEFAULT (1)
    );
    PRINT '  sec.Role                          created';
END
ELSE PRINT '  sec.Role                          skipped';
GO

IF OBJECT_ID('sec.AppUser') IS NULL
BEGIN
    CREATE TABLE sec.AppUser
    (
        AppUserId   int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_AppUser PRIMARY KEY,
        LoginName   nvarchar(128) NOT NULL CONSTRAINT UQ_sec_AppUser_Login UNIQUE,
        DisplayName nvarchar(200) NOT NULL,
        PersonnelNo nvarchar(30)  NULL,
        Email       nvarchar(200) NULL,
        /* Rule 3 of the precedence: an authorization that has ended denies everything. */
        AuthorizationEndsOn date  NULL,
        /* Rule 1: the seeded administrator, so a fresh database is reachable. */
        IsBootstrap bit           NOT NULL CONSTRAINT DF_sec_AppUser_Boot   DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sec_AppUser_Active DEFAULT (1),
        AddedByLogin nvarchar(128) NULL,
        AddedOnUtc  datetime2(3)  NOT NULL CONSTRAINT DF_sec_AppUser_On DEFAULT (SYSUTCDATETIME())
    );
    PRINT '  sec.AppUser                       created';
END
ELSE PRINT '  sec.AppUser                       skipped';
GO

IF OBJECT_ID('sec.UserRole') IS NULL
BEGIN
    CREATE TABLE sec.UserRole
    (
        AppUserId int NOT NULL CONSTRAINT FK_sec_UserRole_User REFERENCES sec.AppUser(AppUserId),
        RoleId    int NOT NULL CONSTRAINT FK_sec_UserRole_Role REFERENCES sec.Role(RoleId),
        CONSTRAINT PK_sec_UserRole PRIMARY KEY (AppUserId, RoleId)
    );
    PRINT '  sec.UserRole                      created';
END
ELSE PRINT '  sec.UserRole                      skipped';
GO

IF OBJECT_ID('sec.RoleScreenGrant') IS NULL
BEGIN
    CREATE TABLE sec.RoleScreenGrant
    (
        RoleId     int      NOT NULL CONSTRAINT FK_sec_RSG_Role   REFERENCES sec.Role(RoleId),
        ScreenId   int      NOT NULL CONSTRAINT FK_sec_RSG_Screen REFERENCES cfg.Screen(ScreenId),
        GrantValue smallint NOT NULL,
        CONSTRAINT PK_sec_RoleScreenGrant PRIMARY KEY (RoleId, ScreenId),
        CONSTRAINT CK_sec_RSG_Value CHECK (GrantValue IN (0, 1, 2))
    );
    PRINT '  sec.RoleScreenGrant               created';
END
ELSE PRINT '  sec.RoleScreenGrant               skipped';
GO

/* Rule 4: a user override replaces the role rule outright, and may widen or narrow it.
   This is where the legacy dbo.UserPolicies rows land when they are migrated.          */
IF OBJECT_ID('sec.UserScreenGrant') IS NULL
BEGIN
    CREATE TABLE sec.UserScreenGrant
    (
        AppUserId  int      NOT NULL CONSTRAINT FK_sec_USG_User   REFERENCES sec.AppUser(AppUserId),
        ScreenId   int      NOT NULL CONSTRAINT FK_sec_USG_Screen REFERENCES cfg.Screen(ScreenId),
        GrantValue smallint NOT NULL,
        Note       nvarchar(400) NULL,
        GrantedByLogin nvarchar(128) NULL,
        GrantedOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sec_USG_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sec_UserScreenGrant PRIMARY KEY (AppUserId, ScreenId),
        CONSTRAINT CK_sec_USG_Value CHECK (GrantValue IN (0, 1, 2))
    );
    PRINT '  sec.UserScreenGrant               created';
END
ELSE PRINT '  sec.UserScreenGrant               skipped';
GO

IF OBJECT_ID('sec.UserOrgGrant') IS NULL
BEGIN
    CREATE TABLE sec.UserOrgGrant
    (
        AppUserId int          NOT NULL CONSTRAINT FK_sec_UOG_User REFERENCES sec.AppUser(AppUserId),
        OrgCode   nvarchar(40) NOT NULL,
        GrantedByLogin nvarchar(128) NULL,
        GrantedOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sec_UOG_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sec_UserOrgGrant PRIMARY KEY (AppUserId, OrgCode)
    );
    PRINT '  sec.UserOrgGrant                  created';
END
ELSE PRINT '  sec.UserOrgGrant                  skipped';
GO

/* An explicit, auditable list of logins that see every organisation. */
IF OBJECT_ID('sec.RlsBypass') IS NULL
BEGIN
    CREATE TABLE sec.RlsBypass
    (
        AppUserId int NOT NULL CONSTRAINT PK_sec_RlsBypass PRIMARY KEY
                      CONSTRAINT FK_sec_RlsBypass_User REFERENCES sec.AppUser(AppUserId),
        Reason    nvarchar(400) NULL,
        GrantedByLogin nvarchar(128) NULL,
        GrantedOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sec_RlsBypass_On DEFAULT (SYSUTCDATETIME())
    );
    PRINT '  sec.RlsBypass                     created';
END
ELSE PRINT '  sec.RlsBypass                     skipped';
GO

/* =====================================================================================
   Row-level security
   ===================================================================================== */

/* sec.fn_UserOrgScope — every organisation code this login may read.  A grant on a node
   reaches every descendant through the closure table, so the tree is walked once at load
   time rather than per row at read time.                                                */
CREATE OR ALTER FUNCTION sec.fn_UserOrgScope (@LoginName nvarchar(128))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    /* A login on the bypass list sees every organisation. */
    SELECT n.OrgCode
    FROM sel.OrgNode n
    WHERE EXISTS (SELECT 1 FROM sec.RlsBypass b
                  JOIN sec.AppUser u ON u.AppUserId = b.AppUserId
                  WHERE u.LoginName = @LoginName AND u.IsActive = 1)
    UNION
    /* Otherwise, the granted nodes and everything under them. */
    SELECT a.OrgCode
    FROM sec.UserOrgGrant g
    JOIN sec.AppUser u ON u.AppUserId = g.AppUserId AND u.IsActive = 1
    JOIN sel.OrgAncestor a ON a.AncestorOrgCode = g.OrgCode
    WHERE u.LoginName = @LoginName;
GO
PRINT '  sec.fn_UserOrgScope               applied';
GO

/* =====================================================================================
   Screen access — the shipped precedence, in one place
   ===================================================================================== */

/* sec.fn_ScreenAccessAsOf — the decision, against an explicit as-of date.

   1  Bootstrap         the seeded administrator, so a fresh database is reachable
   2  Not registered    the login has no sec.AppUser row -> deny
   3  Expired           AuthorizationEndsOn < AsOf -> deny
   4  User override     replaces the role rule outright, and may widen or narrow it
   5  Role policy       sec.RoleScreenGrant
   6  No rule           deny

   An auditor's read-only flag is applied last: no grant can give it write.             */
CREATE OR ALTER FUNCTION sec.fn_ScreenAccessAsOf
(
    @LoginName  nvarchar(128),
    @ScreenCode nvarchar(160),
    @AsOf       date
)
RETURNS smallint
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @userId int, @endsOn date, @isBootstrap bit, @isActive bit;

    SELECT @userId = u.AppUserId, @endsOn = u.AuthorizationEndsOn,
           @isBootstrap = u.IsBootstrap, @isActive = u.IsActive
    FROM sec.AppUser u WHERE u.LoginName = @LoginName;

    /* 2 — not registered. */
    IF @userId IS NULL OR @isActive = 0 RETURN 0;

    DECLARE @screenId int;
    SELECT @screenId = s.ScreenId FROM cfg.Screen s
    WHERE s.ScreenCode = @ScreenCode AND s.IsActive = 1;

    /* An unknown screen is a deny, not an allow: a screen that is not registered has
       no rule, and rule 6 says no rule denies. */
    IF @screenId IS NULL RETURN 0;

    /* Is this login read-only by role?  Needed for the final cap. */
    DECLARE @roleReadOnly bit = 0;
    IF EXISTS (SELECT 1 FROM sec.UserRole ur
               JOIN sec.Role r ON r.RoleId = ur.RoleId
               WHERE ur.AppUserId = @userId AND r.IsReadOnly = 1)
        SET @roleReadOnly = 1;

    /* 1 — bootstrap. */
    IF @isBootstrap = 1
        RETURN CASE WHEN @roleReadOnly = 1 THEN 1 ELSE 2 END;

    /* 3 — expired. */
    IF @endsOn IS NOT NULL AND @endsOn < @AsOf RETURN 0;

    /* 4 — user override replaces the role rule outright. */
    DECLARE @grant smallint;
    SELECT @grant = g.GrantValue FROM sec.UserScreenGrant g
    WHERE g.AppUserId = @userId AND g.ScreenId = @screenId;

    /* 5 — role policy.  Where a login holds several roles the most generous wins,
       because a role is a grant and holding two grants cannot take access away. */
    IF @grant IS NULL
        SELECT @grant = MAX(rsg.GrantValue)
        FROM sec.RoleScreenGrant rsg
        JOIN sec.UserRole ur ON ur.RoleId = rsg.RoleId
        JOIN sec.Role r ON r.RoleId = ur.RoleId AND r.IsActive = 1
        WHERE ur.AppUserId = @userId AND rsg.ScreenId = @screenId;

    /* 6 — no rule. */
    IF @grant IS NULL RETURN 0;

    /* The read-only cap, applied last. */
    IF @roleReadOnly = 1 AND @grant > 1 SET @grant = 1;

    RETURN @grant;
END
GO
PRINT '  sec.fn_ScreenAccessAsOf           applied';
GO

/* sec.fn_ScreenAccess — the two-argument form every procedure calls.  It resolves the
   as-of date from configuration so a caller cannot forget to pass one.                */
/* Not schema bound: it calls cfg.fn_SettingText and sec.fn_ScreenAccessAsOf, and binding
   a caller is what stops those two being re-applied on a second run of the migrations. */
CREATE OR ALTER FUNCTION sec.fn_ScreenAccess (@LoginName nvarchar(128), @ScreenCode nvarchar(160))
RETURNS smallint
AS
BEGIN
    DECLARE @asOf date = TRY_CONVERT(date, cfg.fn_SettingText(N'AS_OF_OVERRIDE'));
    IF @asOf IS NULL SET @asOf = CAST(SYSUTCDATETIME() AS date);
    RETURN sec.fn_ScreenAccessAsOf(@LoginName, @ScreenCode, @asOf);
END
GO
PRINT '  sec.fn_ScreenAccess               applied';
GO

/* sec.fn_ScreenAccessRule — which of the six rules decided, so the access screen can
   show the reason rather than only the outcome.                                        */
CREATE OR ALTER FUNCTION sec.fn_ScreenAccessRule
(
    @LoginName  nvarchar(128),
    @ScreenCode nvarchar(160),
    @AsOf       date
)
RETURNS nvarchar(40)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @userId int, @endsOn date, @isBootstrap bit, @isActive bit;
    SELECT @userId = u.AppUserId, @endsOn = u.AuthorizationEndsOn,
           @isBootstrap = u.IsBootstrap, @isActive = u.IsActive
    FROM sec.AppUser u WHERE u.LoginName = @LoginName;

    IF @userId IS NULL OR @isActive = 0 RETURN N'NOT_REGISTERED';
    IF @isBootstrap = 1 RETURN N'BOOTSTRAP';
    IF @endsOn IS NOT NULL AND @endsOn < @AsOf RETURN N'EXPIRED';

    DECLARE @screenId int;
    SELECT @screenId = ScreenId FROM cfg.Screen WHERE ScreenCode = @ScreenCode AND IsActive = 1;
    IF @screenId IS NULL RETURN N'NO_RULE';

    IF EXISTS (SELECT 1 FROM sec.UserScreenGrant g
               WHERE g.AppUserId = @userId AND g.ScreenId = @screenId)
        RETURN N'USER_OVERRIDE';

    IF EXISTS (SELECT 1 FROM sec.RoleScreenGrant rsg
               JOIN sec.UserRole ur ON ur.RoleId = rsg.RoleId
               WHERE ur.AppUserId = @userId AND rsg.ScreenId = @screenId)
        RETURN N'ROLE_POLICY';

    RETURN N'NO_RULE';
END
GO
PRINT '  sec.fn_ScreenAccessRule           applied';
GO

/* sec.fn_IsReadOnlyUser — the auditor flag, read by IUserContext once per request. */
CREATE OR ALTER FUNCTION sec.fn_IsReadOnlyUser (@LoginName nvarchar(128))
RETURNS bit
WITH SCHEMABINDING
AS
BEGIN
    IF EXISTS (SELECT 1 FROM sec.AppUser u
               JOIN sec.UserRole ur ON ur.AppUserId = u.AppUserId
               JOIN sec.Role r ON r.RoleId = ur.RoleId
               WHERE u.LoginName = @LoginName AND r.IsReadOnly = 1)
        RETURN 1;
    RETURN 0;
END
GO
PRINT '  sec.fn_IsReadOnlyUser             applied';
GO

/* sec.fn_CanEditCycle — a cycle design is editable by its owner or delegate, or an
   administrator, and never once Closed.                                                */
CREATE OR ALTER FUNCTION sec.fn_CanEditCycle (@LoginName nvarchar(128), @CycleId int)
RETURNS bit
AS
BEGIN
    IF @CycleId IS NULL RETURN 0;

    /* A closed cycle is never changed, only copied. */
    IF sel.fn_CycleStatusCode(@CycleId) = N'CLOSED' RETURN 0;

    /* An auditor never writes, whatever else is true. */
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1 RETURN 0;

    /* The design screen's own write grant is the floor. */
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') < 2 RETURN 0;

    IF EXISTS (SELECT 1 FROM sel.Cycle c
               WHERE c.CycleId = @CycleId
                 AND (c.OwnerLogin = @LoginName OR c.DelegateLogin = @LoginName))
        RETURN 1;

    /* An administrator may edit any design. */
    IF EXISTS (SELECT 1 FROM sec.AppUser u
               JOIN sec.UserRole ur ON ur.AppUserId = u.AppUserId
               JOIN sec.Role r ON r.RoleId = ur.RoleId
               WHERE u.LoginName = @LoginName AND u.IsActive = 1 AND r.RoleCode = N'ADMIN')
        RETURN 1;

    RETURN 0;
END
GO
PRINT '  sec.fn_CanEditCycle               applied';
GO

/* sec.fn_CycleEditRefusal — the read-only bar states which reason applies. */
CREATE OR ALTER FUNCTION sec.fn_CycleEditRefusal (@LoginName nvarchar(128), @CycleId int)
RETURNS nvarchar(600)
AS
BEGIN
    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 1 RETURN NULL;
    IF sel.fn_CycleStatusCode(@CycleId) = N'CLOSED' RETURN cfg.fn_Message(N'CLOSED_CYCLE');
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1 RETURN cfg.fn_Message(N'READONLY_REFUSAL');
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') < 2 RETURN cfg.fn_Message(N'READONLY_REFUSAL');
    RETURN cfg.fn_Message(N'NOT_OWNER_REFUSAL');
END
GO
PRINT '  sec.fn_CycleEditRefusal           applied';
GO

/* =====================================================================================
   Procedures — the Access control and Row-level security screens
   ===================================================================================== */

/* sec.usp_User_Context — resolved once per request into IUserContext. */
CREATE OR ALTER PROCEDURE sec.usp_User_Context
    @LoginName nvarchar(128),
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT u.AppUserId, u.LoginName, u.DisplayName, u.PersonnelNo, u.Email,
           u.AuthorizationEndsOn, u.IsBootstrap, u.IsActive,
           RoleCode = (SELECT TOP (1) r.RoleCode FROM sec.UserRole ur
                       JOIN sec.Role r ON r.RoleId = ur.RoleId
                       WHERE ur.AppUserId = u.AppUserId ORDER BY r.SortOrder),
           RoleName = (SELECT TOP (1) r.Name FROM sec.UserRole ur
                       JOIN sec.Role r ON r.RoleId = ur.RoleId
                       WHERE ur.AppUserId = u.AppUserId ORDER BY r.SortOrder),
           IsReadOnly = sec.fn_IsReadOnlyUser(u.LoginName),
           OrgScopeCount = (SELECT COUNT(*) FROM sec.fn_UserOrgScope(u.LoginName)),
           HasRlsBypass = CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sec.RlsBypass b WHERE b.AppUserId = u.AppUserId)
                               THEN 1 ELSE 0 END),
           /* "Authorization ended" / "Ends within four months", in words. */
           AuthorizationNote =
               CASE WHEN u.AuthorizationEndsOn IS NULL THEN NULL
                    WHEN u.AuthorizationEndsOn < @AsOf THEN cfg.fn_Message(N'AUTH_ENDED')
                    WHEN u.AuthorizationEndsOn < DATEADD(MONTH, 4, @AsOf) THEN cfg.fn_Message(N'AUTH_ENDING')
                    ELSE NULL END,
           AsOf = @AsOf
    FROM sec.AppUser u
    WHERE u.LoginName = @LoginName;
END
GO
PRINT '  sec.usp_User_Context              applied';
GO

/* sec.usp_Policy_Matrix — roles, screens and the grant matrix.  "No grant" is a
   visible third state, not an empty cell, so the matrix returns a row for every pair
   and a NULL grant means no rule.                                                      */
CREATE OR ALTER PROCEDURE sec.usp_Policy_Matrix
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT RoleId, RoleCode, Name, Description, IsReadOnly, SortOrder, IsActive,
           UserCount = (SELECT COUNT(*) FROM sec.UserRole ur WHERE ur.RoleId = sec.Role.RoleId)
    FROM sec.Role ORDER BY SortOrder, Name;

    SELECT s.ScreenId, s.ScreenCode, s.Name, s.AreaName, s.IsInMenu, s.SortOrder,
           g.Caption AS GroupCaption, g.SortOrder AS GroupSort
    FROM cfg.Screen s
    LEFT JOIN cfg.MenuGroup g ON g.MenuGroupId = s.MenuGroupId
    WHERE s.IsActive = 1
    ORDER BY g.SortOrder, s.SortOrder, s.Name;

    /* One row per (role, screen): GrantValue NULL means no rule. */
    SELECT r.RoleId, s.ScreenId, rsg.GrantValue
    FROM sec.Role r
    CROSS JOIN cfg.Screen s
    LEFT JOIN sec.RoleScreenGrant rsg ON rsg.RoleId = r.RoleId AND rsg.ScreenId = s.ScreenId
    WHERE s.IsActive = 1;
END
GO
PRINT '  sec.usp_Policy_Matrix             applied';
GO

/* sec.usp_User_List — the users table with its expiry wording and override count. */
CREATE OR ALTER PROCEDURE sec.usp_User_List
    @LoginName nvarchar(128),
    @AsOf      date = NULL,
    @Search    nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT u.AppUserId, u.LoginName, u.DisplayName, u.PersonnelNo, u.Email,
           u.AuthorizationEndsOn, u.IsBootstrap, u.IsActive, u.AddedByLogin, u.AddedOnUtc,
           RoleCode = (SELECT TOP (1) r.RoleCode FROM sec.UserRole ur
                       JOIN sec.Role r ON r.RoleId = ur.RoleId
                       WHERE ur.AppUserId = u.AppUserId ORDER BY r.SortOrder),
           RoleName = (SELECT TOP (1) r.Name FROM sec.UserRole ur
                       JOIN sec.Role r ON r.RoleId = ur.RoleId
                       WHERE ur.AppUserId = u.AppUserId ORDER BY r.SortOrder),
           OverrideCount = (SELECT COUNT(*) FROM sec.UserScreenGrant g WHERE g.AppUserId = u.AppUserId),
           OrgGrantCount = (SELECT COUNT(*) FROM sec.UserOrgGrant og WHERE og.AppUserId = u.AppUserId),
           OrgScopeCount = (SELECT COUNT(*) FROM sec.fn_UserOrgScope(u.LoginName)),
           AuthorizationNote =
               CASE WHEN u.AuthorizationEndsOn IS NULL THEN NULL
                    WHEN u.AuthorizationEndsOn < @AsOf THEN cfg.fn_Message(N'AUTH_ENDED')
                    WHEN u.AuthorizationEndsOn < DATEADD(MONTH, 4, @AsOf) THEN cfg.fn_Message(N'AUTH_ENDING')
                    ELSE NULL END,
           AuthorizationRole =
               CASE WHEN u.AuthorizationEndsOn IS NULL THEN NULL
                    WHEN u.AuthorizationEndsOn < @AsOf THEN N'danger'
                    WHEN u.AuthorizationEndsOn < DATEADD(MONTH, 4, @AsOf) THEN N'warning'
                    ELSE NULL END
    FROM sec.AppUser u
    WHERE (@Search IS NULL OR u.LoginName LIKE N'%' + @Search + N'%' OR u.DisplayName LIKE N'%' + @Search + N'%')
    ORDER BY u.DisplayName;

    /* The per-user overrides. */
    SELECT g.AppUserId, u.LoginName, g.ScreenId, s.ScreenCode, s.Name AS ScreenName,
           g.GrantValue, g.Note, g.GrantedByLogin, g.GrantedOnUtc
    FROM sec.UserScreenGrant g
    JOIN sec.AppUser u ON u.AppUserId = g.AppUserId
    JOIN cfg.Screen s ON s.ScreenId = g.ScreenId
    ORDER BY u.DisplayName, s.SortOrder;
END
GO
PRINT '  sec.usp_User_List                 applied';
GO

/* sec.usp_ScreenAccess_Explain — the precedence made visible for one login: what each
   screen resolves to, and which of the six rules decided it.                          */
CREATE OR ALTER PROCEDURE sec.usp_ScreenAccess_Explain
    @LoginName    nvarchar(128),
    @TargetLogin  nvarchar(128),
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT s.ScreenId, s.ScreenCode, s.Name, s.AreaName, g.Caption AS GroupCaption,
           GrantValue = sec.fn_ScreenAccessAsOf(@TargetLogin, s.ScreenCode, @AsOf),
           RuleCode   = sec.fn_ScreenAccessRule(@TargetLogin, s.ScreenCode, @AsOf)
    FROM cfg.Screen s
    LEFT JOIN cfg.MenuGroup g ON g.MenuGroupId = s.MenuGroupId
    WHERE s.IsActive = 1
    ORDER BY g.SortOrder, s.SortOrder, s.Name;
END
GO
PRINT '  sec.usp_ScreenAccess_Explain      applied';
GO

/* sec.usp_Rls_Compare — two viewers' scopes side by side: units, pool and HIPO counts. */
CREATE OR ALTER PROCEDURE sec.usp_Rls_Compare
    @LoginName   nvarchar(128),
    @LoginA      nvarchar(128),
    @LoginB      nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT WhichLogin = N'A', Login = @LoginA,
           Units = (SELECT COUNT(*) FROM sec.fn_UserOrgScope(@LoginA)),
           People = (SELECT COUNT(*) FROM sel.Employee e
                     JOIN sec.fn_UserOrgScope(@LoginA) s ON s.OrgCode = e.OrgCode
                     WHERE e.IsActive = 1),
           InPools = (SELECT COUNT(DISTINCT c.PersonnelNo) FROM sel.CycleCandidate c
                      JOIN sec.fn_UserOrgScope(@LoginA) s ON s.OrgCode = c.OrgCode)
    UNION ALL
    SELECT N'B', @LoginB,
           (SELECT COUNT(*) FROM sec.fn_UserOrgScope(@LoginB)),
           (SELECT COUNT(*) FROM sel.Employee e
            JOIN sec.fn_UserOrgScope(@LoginB) s ON s.OrgCode = e.OrgCode WHERE e.IsActive = 1),
           (SELECT COUNT(DISTINCT c.PersonnelNo) FROM sel.CycleCandidate c
            JOIN sec.fn_UserOrgScope(@LoginB) s ON s.OrgCode = c.OrgCode);
END
GO
PRINT '  sec.usp_Rls_Compare               applied';
GO

/* sec.usp_ScreenAccess_Check — the ScreenAccess authorization handler's one call.

   The handler could not call sec.fn_ScreenAccess directly without holding SQL text, and
   there is no SQL text in C#, so the function gets a procedure in front of it.  It returns
   the grant, the rule that decided it, and the refusal sentence to render, so the handler
   maps a row to a decision and composes nothing itself. */
CREATE OR ALTER PROCEDURE sec.usp_ScreenAccess_Check
    @LoginName  nvarchar(128),
    @ScreenCode nvarchar(160),
    @AsOf       date = NULL,
    @NeedsWrite bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @grant smallint = sec.fn_ScreenAccessAsOf(@LoginName, @ScreenCode, @AsOf);
    DECLARE @rule nvarchar(40) = sec.fn_ScreenAccessRule(@LoginName, @ScreenCode, @AsOf);

    SELECT GrantValue = @grant,
           RuleCode   = @rule,
           CanRead    = CONVERT(bit, CASE WHEN @grant >= 1 THEN 1 ELSE 0 END),
           CanWrite   = CONVERT(bit, CASE WHEN @grant >= 2 THEN 1 ELSE 0 END),
           IsAllowed  = CONVERT(bit, CASE WHEN @NeedsWrite = 1 THEN CASE WHEN @grant >= 2 THEN 1 ELSE 0 END
                             ELSE CASE WHEN @grant >= 1 THEN 1 ELSE 0 END END),
           ScreenName = (SELECT Name FROM cfg.Screen WHERE ScreenCode = @ScreenCode),
           /* The sentence the refusal screen renders.  Which of the six rules applied is
              what makes a denial explainable rather than mysterious. */
           Refusal =
               CASE WHEN (@NeedsWrite = 0 AND @grant >= 1) OR (@NeedsWrite = 1 AND @grant >= 2) THEN NULL
                    WHEN @rule = N'NOT_REGISTERED'
                         THEN N'Your login is not registered in Maseera, so nothing is open to you yet. '
                            + N'An administrator adds people on the Access control screen.'
                    WHEN @rule = N'EXPIRED'
                         THEN N'Your authorization ended, so every screen is closed until it is renewed.'
                    WHEN @NeedsWrite = 1 AND @grant = 1
                         THEN cfg.fn_Message(N'READONLY_REFUSAL')
                    WHEN @rule = N'USER_OVERRIDE'
                         THEN N'A grant set against you denies this screen.'
                    WHEN @rule = N'ROLE_POLICY'
                         THEN N'Your role does not open this screen.'
                    ELSE N'Nothing grants you this screen.' END;
END
GO
PRINT '  sec.usp_ScreenAccess_Check        applied';
GO

PRINT '== 06_security complete ==============================================';
GO
