/* =====================================================================================
   01_config_engine.sql  —  the configuration engine
   -------------------------------------------------------------------------------------
   Every closed set in Maseera lives here: domains and their values, comparison operators,
   settings, screens, menu groups and messages.  Nothing in C#, Razor or JavaScript may
   carry a literal that belongs in one of these tables.

   Idempotent: creates what is missing, prints a receipt line for what it skipped.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 01_config_engine ==================================================';
GO

/* --- schemas ------------------------------------------------------------------ */
IF SCHEMA_ID('cfg')   IS NULL EXEC('CREATE SCHEMA cfg');   ELSE PRINT '  schema cfg    skipped';
GO
IF SCHEMA_ID('sel')   IS NULL EXEC('CREATE SCHEMA sel');   ELSE PRINT '  schema sel    skipped';
GO
IF SCHEMA_ID('sec')   IS NULL EXEC('CREATE SCHEMA sec');   ELSE PRINT '  schema sec    skipped';
GO
IF SCHEMA_ID('stg')   IS NULL EXEC('CREATE SCHEMA stg');   ELSE PRINT '  schema stg    skipped';
GO
IF SCHEMA_ID('audit') IS NULL EXEC('CREATE SCHEMA audit'); ELSE PRINT '  schema audit  skipped';
GO

/* --- cfg.Domain ---------------------------------------------------------------
   A closed set of values the application must not hardcode.                      */
IF OBJECT_ID('cfg.Domain') IS NULL
BEGIN
    CREATE TABLE cfg.Domain
    (
        DomainId    int            IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_Domain PRIMARY KEY,
        DomainCode  nvarchar(60)   NOT NULL CONSTRAINT UQ_cfg_Domain_Code UNIQUE,
        Name        nvarchar(120)  NOT NULL,
        Description nvarchar(400)  NULL,
        /* A system domain's codes are referenced by the engine and may not be deleted. */
        IsSystem    bit            NOT NULL CONSTRAINT DF_cfg_Domain_IsSystem DEFAULT (0),
        SortOrder   int            NOT NULL CONSTRAINT DF_cfg_Domain_Sort     DEFAULT (0)
    );
    PRINT '  cfg.Domain                        created';
END
ELSE PRINT '  cfg.Domain                        skipped';
GO

/* --- cfg.DomainValue ----------------------------------------------------------
   SemanticRole names a *meaning* (positive, warning, danger, ...).  The stylesheet
   decides what that looks like; the database never carries a hex colour.          */
IF OBJECT_ID('cfg.DomainValue') IS NULL
BEGIN
    CREATE TABLE cfg.DomainValue
    (
        DomainValueId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_DomainValue PRIMARY KEY,
        DomainId      int           NOT NULL CONSTRAINT FK_cfg_DomainValue_Domain REFERENCES cfg.Domain(DomainId),
        ValueCode     nvarchar(60)  NOT NULL,
        Name          nvarchar(160) NOT NULL,
        Description   nvarchar(400) NULL,
        SemanticRole  nvarchar(40)  NULL,
        SortOrder     int           NOT NULL CONSTRAINT DF_cfg_DomainValue_Sort     DEFAULT (0),
        IsActive      bit           NOT NULL CONSTRAINT DF_cfg_DomainValue_Active   DEFAULT (1),
        IsSystem      bit           NOT NULL CONSTRAINT DF_cfg_DomainValue_IsSystem DEFAULT (0),
        CONSTRAINT UQ_cfg_DomainValue UNIQUE (DomainId, ValueCode)
    );
    CREATE INDEX IX_cfg_DomainValue_Domain ON cfg.DomainValue (DomainId, SortOrder) INCLUDE (ValueCode, Name, SemanticRole, IsActive);
    PRINT '  cfg.DomainValue                   created';
END
ELSE PRINT '  cfg.DomainValue                   skipped';
GO

/* --- cfg.Operator -------------------------------------------------------------
   A comparison the criteria builder and the rule editor may offer.  SqlTemplate is
   the only place the SQL shape of an operator is written down.  Arity says how many
   values it collects; AppliesTo says which field data types may use it.            */
IF OBJECT_ID('cfg.Operator') IS NULL
BEGIN
    CREATE TABLE cfg.Operator
    (
        OperatorId   int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_Operator PRIMARY KEY,
        OperatorCode nvarchar(30)  NOT NULL CONSTRAINT UQ_cfg_Operator_Code UNIQUE,
        /* Reads in words, because the rule is shown back to the user as a sentence. */
        Name         nvarchar(60)  NOT NULL,
        SqlTemplate  nvarchar(400) NOT NULL,
        AppliesTo    nvarchar(120) NOT NULL,   -- comma separated data types: text,number,date,bit
        Arity        tinyint       NOT NULL,   -- how many values the editor collects
        SortOrder    int           NOT NULL CONSTRAINT DF_cfg_Operator_Sort   DEFAULT (0),
        IsActive     bit           NOT NULL CONSTRAINT DF_cfg_Operator_Active DEFAULT (1)
    );
    PRINT '  cfg.Operator                      created';
END
ELSE PRINT '  cfg.Operator                      skipped';
GO

/* --- cfg.Setting --------------------------------------------------------------- */
IF OBJECT_ID('cfg.Setting') IS NULL
BEGIN
    CREATE TABLE cfg.Setting
    (
        SettingId   int            IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_Setting PRIMARY KEY,
        SettingKey  nvarchar(80)   NOT NULL CONSTRAINT UQ_cfg_Setting_Key UNIQUE,
        TextValue   nvarchar(400)  NULL,
        NumValue    decimal(18,4)  NULL,
        Description nvarchar(400)  NULL
    );
    PRINT '  cfg.Setting                       created';
END
ELSE PRINT '  cfg.Setting                       skipped';
GO

/* --- cfg.MenuGroup ------------------------------------------------------------- */
IF OBJECT_ID('cfg.MenuGroup') IS NULL
BEGIN
    CREATE TABLE cfg.MenuGroup
    (
        MenuGroupId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_MenuGroup PRIMARY KEY,
        GroupCode   nvarchar(40)  NOT NULL CONSTRAINT UQ_cfg_MenuGroup_Code UNIQUE,
        Caption     nvarchar(80)  NOT NULL,
        /* The one-line "what this group is for" the prototype shows under the caption. */
        Subtitle    nvarchar(160) NULL,
        SortOrder   int           NOT NULL CONSTRAINT DF_cfg_MenuGroup_Sort   DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_cfg_MenuGroup_Active DEFAULT (1)
    );
    PRINT '  cfg.MenuGroup                     created';
END
ELSE PRINT '  cfg.MenuGroup                     skipped';
GO

/* --- cfg.Screen ---------------------------------------------------------------
   ScreenCode is the shipped route path.  The legacy dbo.Policies rows are keyed on
   these paths, so they are data, not a naming convention we are free to change.     */
IF OBJECT_ID('cfg.Screen') IS NULL
BEGIN
    CREATE TABLE cfg.Screen
    (
        ScreenId       int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_Screen PRIMARY KEY,
        ScreenCode     nvarchar(160) NOT NULL CONSTRAINT UQ_cfg_Screen_Code UNIQUE,
        Name           nvarchar(120) NOT NULL,
        AreaName       nvarchar(60)  NOT NULL,
        ControllerName nvarchar(60)  NOT NULL,
        ActionName     nvarchar(60)  NOT NULL,
        MenuGroupId    int           NULL CONSTRAINT FK_cfg_Screen_MenuGroup REFERENCES cfg.MenuGroup(MenuGroupId),
        /* Stage screens are faces of a cycle, reached from the cycle, never from the menu. */
        IsInMenu       bit           NOT NULL CONSTRAINT DF_cfg_Screen_InMenu DEFAULT (1),
        SortOrder      int           NOT NULL CONSTRAINT DF_cfg_Screen_Sort   DEFAULT (0),
        IsActive       bit           NOT NULL CONSTRAINT DF_cfg_Screen_Active DEFAULT (1)
    );
    PRINT '  cfg.Screen                        created';
END
ELSE PRINT '  cfg.Screen                        skipped';
GO

/* --- cfg.Message ---------------------------------------------------------------
   Every user-visible sentence that can vary.  A view never holds a string literal
   that an administrator might reasonably want to reword.                           */
IF OBJECT_ID('cfg.Message') IS NULL
BEGIN
    CREATE TABLE cfg.Message
    (
        MessageId   int            IDENTITY(1,1) NOT NULL CONSTRAINT PK_cfg_Message PRIMARY KEY,
        MessageKey  nvarchar(80)   NOT NULL CONSTRAINT UQ_cfg_Message_Key UNIQUE,
        MessageText nvarchar(1000) NOT NULL,
        Description nvarchar(400)  NULL
    );
    PRINT '  cfg.Message                       created';
END
ELSE PRINT '  cfg.Message                       skipped';
GO

/* --- audit.ChangeLog -----------------------------------------------------------
   Append only.  Nothing in the application deletes from it.                        */
IF OBJECT_ID('audit.ChangeLog') IS NULL
BEGIN
    CREATE TABLE audit.ChangeLog
    (
        ChangeLogId  bigint         IDENTITY(1,1) NOT NULL CONSTRAINT PK_audit_ChangeLog PRIMARY KEY,
        TableName    nvarchar(160)  NOT NULL,
        KeyText      nvarchar(200)  NULL,
        ActionCode   nvarchar(20)   NOT NULL,        -- INSERT | UPDATE | DELETE
        BeforeJson   nvarchar(max)  NULL,
        AfterJson    nvarchar(max)  NULL,
        LoginName    nvarchar(128)  NOT NULL,
        ChangedOnUtc datetime2(3)   NOT NULL CONSTRAINT DF_audit_ChangeLog_On DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_audit_ChangeLog_Table ON audit.ChangeLog (TableName, ChangedOnUtc DESC);
    CREATE INDEX IX_audit_ChangeLog_Login ON audit.ChangeLog (LoginName, ChangedOnUtc DESC);
    PRINT '  audit.ChangeLog                   created';
END
ELSE PRINT '  audit.ChangeLog                   skipped';
GO

/* --- table valued parameter types ----------------------------------------------
   Bulk writes pass one of these, never a loop of single calls and never a
   comma-joined string.                                                             */
IF TYPE_ID('dbo.IdList') IS NULL
BEGIN
    CREATE TYPE dbo.IdList AS TABLE (Id nvarchar(60) NOT NULL PRIMARY KEY);
    PRINT '  type dbo.IdList                   created';
END
ELSE PRINT '  type dbo.IdList                   skipped';
GO

IF TYPE_ID('dbo.KeyValueList') IS NULL
BEGIN
    CREATE TYPE dbo.KeyValueList AS TABLE
    (
        SeqNo     int            NOT NULL IDENTITY(1,1) PRIMARY KEY,
        [Key]     nvarchar(160)  NOT NULL,
        [Value]   nvarchar(1000) NULL
    );
    PRINT '  type dbo.KeyValueList             created';
END
ELSE PRINT '  type dbo.KeyValueList             skipped';
GO

/* =====================================================================================
   Functions
   ===================================================================================== */

/* cfg.fn_DomainValueId — the id behind a (domain, code) pair.  Returns NULL when the
   code is not in the domain, so a caller can refuse rather than guess.               */
CREATE OR ALTER FUNCTION cfg.fn_DomainValueId (@DomainCode nvarchar(60), @ValueCode nvarchar(60))
RETURNS int
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Id int;
    SELECT @Id = dv.DomainValueId
    FROM cfg.DomainValue dv
    JOIN cfg.Domain d ON d.DomainId = dv.DomainId
    WHERE d.DomainCode = @DomainCode
      AND dv.ValueCode = @ValueCode;
    RETURN @Id;
END
GO
PRINT '  cfg.fn_DomainValueId              applied';
GO

/* cfg.fn_DomainValueCode — the reverse lookup, for rendering a stored id. */
CREATE OR ALTER FUNCTION cfg.fn_DomainValueCode (@DomainValueId int)
RETURNS nvarchar(60)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @Code nvarchar(60);
    SELECT @Code = ValueCode FROM cfg.DomainValue WHERE DomainValueId = @DomainValueId;
    RETURN @Code;
END
GO
PRINT '  cfg.fn_DomainValueCode            applied';
GO

/* cfg.fn_DomainValues — every active value in a domain, in order. */
CREATE OR ALTER FUNCTION cfg.fn_DomainValues (@DomainCode nvarchar(60))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT dv.DomainValueId,
           dv.ValueCode,
           dv.Name,
           dv.Description,
           dv.SemanticRole,
           dv.SortOrder,
           dv.IsActive,
           dv.IsSystem
    FROM cfg.DomainValue dv
    JOIN cfg.Domain d ON d.DomainId = dv.DomainId
    WHERE d.DomainCode = @DomainCode
      AND dv.IsActive = 1;
GO
PRINT '  cfg.fn_DomainValues               applied';
GO

/* cfg.fn_SettingNum / fn_SettingText — a sampling cap, a page size, a weight total,
   a content width.  Never a C# const.                                              */
CREATE OR ALTER FUNCTION cfg.fn_SettingNum (@SettingKey nvarchar(80))
RETURNS decimal(18,4)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @v decimal(18,4);
    SELECT @v = NumValue FROM cfg.Setting WHERE SettingKey = @SettingKey;
    RETURN @v;
END
GO
PRINT '  cfg.fn_SettingNum                 applied';
GO

CREATE OR ALTER FUNCTION cfg.fn_SettingText (@SettingKey nvarchar(80))
RETURNS nvarchar(400)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @v nvarchar(400);
    SELECT @v = TextValue FROM cfg.Setting WHERE SettingKey = @SettingKey;
    RETURN @v;
END
GO
PRINT '  cfg.fn_SettingText                applied';
GO

/* cfg.fn_Message — a user-visible sentence by key, falling back to the key itself so
   a missing row is visible on screen rather than rendering as blank.                */
CREATE OR ALTER FUNCTION cfg.fn_Message (@MessageKey nvarchar(80))
RETURNS nvarchar(1000)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @t nvarchar(1000);
    SELECT @t = MessageText FROM cfg.Message WHERE MessageKey = @MessageKey;
    RETURN ISNULL(@t, N'[' + @MessageKey + N']');
END
GO
PRINT '  cfg.fn_Message                    applied';
GO

/* =====================================================================================
   Procedures
   ===================================================================================== */

/* audit.usp_Log — the single writer for audit.ChangeLog.  Every save and delete calls
   it; nothing else writes the table.                                                 */
CREATE OR ALTER PROCEDURE audit.usp_Log
    @TableName  nvarchar(160),
    @KeyText    nvarchar(200),
    @ActionCode nvarchar(20),
    @BeforeJson nvarchar(max) = NULL,
    @AfterJson  nvarchar(max) = NULL,
    @LoginName  nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT audit.ChangeLog (TableName, KeyText, ActionCode, BeforeJson, AfterJson, LoginName)
    VALUES (@TableName, @KeyText, @ActionCode, @BeforeJson, @AfterJson, @LoginName);
END
GO
PRINT '  audit.usp_Log                     applied';
GO

/* cfg.usp_Menu — the navigation, as the TopNav view component renders it.  The menu is
   never markup in _Layout.cshtml.                                                     */
CREATE OR ALTER PROCEDURE cfg.usp_Menu
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT g.MenuGroupId, g.GroupCode, g.Caption, g.Subtitle, g.SortOrder
    FROM cfg.MenuGroup g
    WHERE g.IsActive = 1
      AND EXISTS (SELECT 1 FROM cfg.Screen s
                  WHERE s.MenuGroupId = g.MenuGroupId AND s.IsInMenu = 1 AND s.IsActive = 1
                    AND sec.fn_ScreenAccess(@LoginName, s.ScreenCode) >= 1)
    ORDER BY g.SortOrder, g.Caption;

    /* The same shape as cfg.usp_Screen_List, column for column: both fill the same
       record, and a set that is one column short is a set that cannot be read at all. */
    SELECT s.ScreenId, s.ScreenCode, s.Name, s.AreaName, s.ControllerName, s.ActionName,
           s.MenuGroupId, g.Caption AS GroupCaption, s.IsInMenu, s.SortOrder, s.IsActive,
           sec.fn_ScreenAccess(@LoginName, s.ScreenCode) AS GrantValue
    FROM cfg.Screen s
    LEFT JOIN cfg.MenuGroup g ON g.MenuGroupId = s.MenuGroupId
    WHERE s.IsInMenu = 1 AND s.IsActive = 1
      AND sec.fn_ScreenAccess(@LoginName, s.ScreenCode) >= 1
    ORDER BY s.MenuGroupId, s.SortOrder, s.Name;
END
GO
PRINT '  cfg.usp_Menu                      applied';
GO

/* cfg.usp_Screen_List — the command palette's registry, and the startup self-check's
   list of screens that must resolve to a controller action.                          */
CREATE OR ALTER PROCEDURE cfg.usp_Screen_List
    @LoginName   nvarchar(128) = NULL,
    @IncludeAll  bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.ScreenId, s.ScreenCode, s.Name, s.AreaName, s.ControllerName, s.ActionName,
           s.MenuGroupId, g.Caption AS GroupCaption, s.IsInMenu, s.SortOrder, s.IsActive,
           CASE WHEN @LoginName IS NULL THEN NULL
                ELSE sec.fn_ScreenAccess(@LoginName, s.ScreenCode) END AS GrantValue
    FROM cfg.Screen s
    LEFT JOIN cfg.MenuGroup g ON g.MenuGroupId = s.MenuGroupId
    WHERE (@IncludeAll = 1 OR s.IsActive = 1)
      AND (@LoginName IS NULL OR sec.fn_ScreenAccess(@LoginName, s.ScreenCode) >= 1)
    ORDER BY g.SortOrder, s.SortOrder, s.Name;
END
GO
PRINT '  cfg.usp_Screen_List               applied';
GO

/* cfg.usp_Domain_List / cfg.usp_DomainValue_List — the Reference data screen. */
CREATE OR ALTER PROCEDURE cfg.usp_Domain_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.DomainId, d.DomainCode, d.Name, d.Description, d.IsSystem, d.SortOrder,
           (SELECT COUNT(*) FROM cfg.DomainValue v WHERE v.DomainId = d.DomainId) AS ValueCount,
           (SELECT COUNT(*) FROM cfg.DomainValue v WHERE v.DomainId = d.DomainId AND v.IsActive = 1) AS ActiveCount
    FROM cfg.Domain d
    ORDER BY d.SortOrder, d.Name;
END
GO
PRINT '  cfg.usp_Domain_List               applied';
GO

CREATE OR ALTER PROCEDURE cfg.usp_DomainValue_List
    @DomainCode nvarchar(60)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT dv.DomainValueId, dv.DomainId, d.DomainCode, dv.ValueCode, dv.Name, dv.Description,
           dv.SemanticRole, dv.SortOrder, dv.IsActive, dv.IsSystem, d.IsSystem AS DomainIsSystem
    FROM cfg.DomainValue dv
    JOIN cfg.Domain d ON d.DomainId = dv.DomainId
    WHERE d.DomainCode = @DomainCode
    ORDER BY dv.SortOrder, dv.Name;
END
GO
PRINT '  cfg.usp_DomainValue_List          applied';
GO

/* cfg.usp_Operator_List — the operators an editor may offer for a given data type.
   The criteria builder filters on AppliesTo; it never holds its own operator list.   */
CREATE OR ALTER PROCEDURE cfg.usp_Operator_List
    @DataType nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT OperatorId, OperatorCode, Name, SqlTemplate, AppliesTo, Arity, SortOrder
    FROM cfg.Operator
    WHERE IsActive = 1
      AND (@DataType IS NULL
           OR N',' + AppliesTo + N',' LIKE N'%,' + @DataType + N',%')
    ORDER BY SortOrder, Name;
END
GO
PRINT '  cfg.usp_Operator_List             applied';
GO

/* cfg.usp_Setting_List / cfg.usp_Message_List — read by the config cache at startup. */
CREATE OR ALTER PROCEDURE cfg.usp_Setting_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SettingId, SettingKey, TextValue, NumValue, Description
    FROM cfg.Setting ORDER BY SettingKey;
END
GO
PRINT '  cfg.usp_Setting_List              applied';
GO

CREATE OR ALTER PROCEDURE cfg.usp_Message_List
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MessageId, MessageKey, MessageText, Description
    FROM cfg.Message ORDER BY MessageKey;
END
GO
PRINT '  cfg.usp_Message_List              applied';
GO

/* cfg.usp_Config_Stamp — the content stamp the configuration cache keys on.
   Part 12.3: editing a rule changes no row count, so a count-based cache key serves a
   stale answer after the edit.  This hashes the *content* of every cfg table, so an
   edit that leaves the row count alone still moves the stamp.                        */
CREATE OR ALTER PROCEDURE cfg.usp_Config_Stamp
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @content nvarchar(max) = N'';

    SELECT @content = @content + CONCAT(d.DomainCode, N'|', dv.ValueCode, N'|', dv.Name, N'|',
                                        ISNULL(dv.SemanticRole, N''), N'|', dv.SortOrder, N'|', dv.IsActive, N';')
    FROM cfg.DomainValue dv JOIN cfg.Domain d ON d.DomainId = dv.DomainId
    ORDER BY d.DomainCode, dv.ValueCode;

    SELECT @content = @content + CONCAT(o.OperatorCode, N'|', o.Name, N'|', o.SqlTemplate, N'|',
                                        o.AppliesTo, N'|', o.Arity, N'|', o.IsActive, N';')
    FROM cfg.Operator o ORDER BY o.OperatorCode;

    SELECT @content = @content + CONCAT(s.SettingKey, N'|', ISNULL(s.TextValue, N''), N'|',
                                        ISNULL(CONVERT(nvarchar(40), s.NumValue), N''), N';')
    FROM cfg.Setting s ORDER BY s.SettingKey;

    SELECT @content = @content + CONCAT(m.MessageKey, N'|', m.MessageText, N';')
    FROM cfg.Message m ORDER BY m.MessageKey;

    SELECT @content = @content + CONCAT(sc.ScreenCode, N'|', sc.Name, N'|', sc.AreaName, N'|',
                                        sc.ControllerName, N'|', sc.ActionName, N'|',
                                        ISNULL(CONVERT(nvarchar(20), sc.MenuGroupId), N''), N'|',
                                        sc.IsInMenu, N'|', sc.SortOrder, N'|', sc.IsActive, N';')
    FROM cfg.Screen sc ORDER BY sc.ScreenCode;

    SELECT @content = @content + CONCAT(g.GroupCode, N'|', g.Caption, N'|', ISNULL(g.Subtitle, N''), N'|',
                                        g.SortOrder, N'|', g.IsActive, N';')
    FROM cfg.MenuGroup g ORDER BY g.GroupCode;

    SELECT CONVERT(varchar(64), HASHBYTES('SHA2_256', @content), 2) AS Stamp,
           LEN(@content) AS ContentLength;
END
GO
PRINT '  cfg.usp_Config_Stamp              applied';
GO

/* cfg.usp_Health_Check — the startup self-check and /Admin/Health.
   Part 5: no SQL text in C#, ever — not even a SELECT 1.  The health check calls a
   procedure too.  Fail loudly at startup, not on the screen that needs the row.      */
CREATE OR ALTER PROCEDURE cfg.usp_Health_Check
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @r TABLE (Grp nvarchar(40), CheckName nvarchar(120), Actual bigint,
                      IsOk bit, Note nvarchar(400), SortOrder int);

    /* Configuration counts must all be non-zero. */
    INSERT @r VALUES ('Configuration', 'cfg.Domain',      (SELECT COUNT(*) FROM cfg.Domain),      NULL, NULL, 10),
                     ('Configuration', 'cfg.DomainValue', (SELECT COUNT(*) FROM cfg.DomainValue), NULL, NULL, 11),
                     ('Configuration', 'cfg.Operator',    (SELECT COUNT(*) FROM cfg.Operator),    NULL, NULL, 12),
                     ('Configuration', 'cfg.Setting',     (SELECT COUNT(*) FROM cfg.Setting),     NULL, NULL, 13),
                     ('Configuration', 'cfg.Screen',      (SELECT COUNT(*) FROM cfg.Screen),      NULL, NULL, 14),
                     ('Configuration', 'cfg.MenuGroup',   (SELECT COUNT(*) FROM cfg.MenuGroup),   NULL, NULL, 15),
                     ('Configuration', 'cfg.Message',     (SELECT COUNT(*) FROM cfg.Message),     NULL, NULL, 16);

    UPDATE @r SET IsOk = CONVERT(bit, CASE WHEN Actual > 0 THEN 1 ELSE 0 END),
                  Note = CASE WHEN Actual > 0 THEN NULL
                              ELSE N'This table is empty. Run 09_reference_data.sql.' END
    WHERE Grp = 'Configuration';

    /* Every registered screen must resolve to an area/controller/action triple. */
    INSERT @r
    SELECT 'Screens', 'Screens missing a controller action',
           COUNT(*),
           CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END,
           CASE WHEN COUNT(*) = 0 THEN NULL
                ELSE N'A registered screen has no controller or action recorded against it.' END,
           20
    FROM cfg.Screen
    WHERE IsActive = 1
      AND (NULLIF(LTRIM(RTRIM(ControllerName)), N'') IS NULL
           OR NULLIF(LTRIM(RTRIM(ActionName)), N'') IS NULL);

    /* Every evidence source must be mapped, or the requirements that name it can
       never be met — and that must be said out loud, not discovered as a zero.       */
    IF OBJECT_ID('sel.EvidenceSource') IS NOT NULL
    BEGIN
        INSERT @r
        SELECT 'Evidence', 'Requirement kinds with no table mapped',
               COUNT(*),
               CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END,
               CASE WHEN COUNT(*) = 0 THEN NULL
                    ELSE cfg.fn_Message(N'SOURCE_UNMAPPED') END,
               30
        FROM sel.EvidenceSource WHERE IsMapped = 0;
    END

    SELECT Grp AS [Group], CheckName, Actual, IsOk, Note
    FROM @r ORDER BY SortOrder;
END
GO
PRINT '  cfg.usp_Health_Check              applied';
GO

PRINT '== 01_config_engine complete =========================================';
GO

/* cfg.usp_Proc_Contract — the parameters and, where asked, the result-set shape of the
   application's procedures.

   Two callers need this.  The runner reads it so it can add @LoginName and @AsOf only to
   the procedures that declare them — that is how "the runner adds both automatically so a
   developer cannot forget" is kept honest without any C# holding SQL text.  The contract
   test reads it to prove every procedure a repository calls exists with the parameters
   that repository passes. */
CREATE OR ALTER PROCEDURE cfg.usp_Proc_Contract
    @ProcName nvarchar(300) = NULL         -- schema.name, or NULL for every one
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ProcName  = s.name + N'.' + p.name,
           SchemaName = s.name,
           ObjectName = p.name,
           ParameterName = pr.name,
           TypeName  = t.name,
           MaxLength = pr.max_length,
           IsOutput  = pr.is_output,
           HasDefault = pr.has_default_value,
           IsTableType = CONVERT(bit, CASE WHEN t.is_table_type = 1 THEN 1 ELSE 0 END),
           OrdinalPos = pr.parameter_id
    FROM sys.procedures p
    JOIN sys.schemas s ON s.schema_id = p.schema_id
    LEFT JOIN sys.parameters pr ON pr.object_id = p.object_id
    LEFT JOIN sys.types t ON t.user_type_id = pr.user_type_id
    WHERE s.name IN (N'cfg', N'sel', N'sec', N'audit')
      AND (@ProcName IS NULL OR s.name + N'.' + p.name = @ProcName)
    ORDER BY s.name, p.name, pr.parameter_id;
END
GO
PRINT '  cfg.usp_Proc_Contract             applied';
GO


/* audit.usp_ChangeLog_List — the configuration change log.  Append only: nothing in the
   application deletes from audit.ChangeLog, and this is the only way it is read. */
CREATE OR ALTER PROCEDURE audit.usp_ChangeLog_List
    @LoginName  nvarchar(128),
    @TableName  nvarchar(160) = NULL,
    @ActorLogin nvarchar(128) = NULL,
    @Search     nvarchar(200) = NULL,
    @PageNo     int = 1,
    @PageSize   int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageNo IS NULL OR @PageNo < 1 SET @PageNo = 1;

    /* The change log is a configuration record, not a person record, so it carries no
       organisation and is gated on the access-control screen instead. */
    IF sec.fn_ScreenAccess(@LoginName, N'/Admin/Policy/') < 1
    BEGIN
        SELECT TOP (0) CAST(NULL AS bigint) AS ChangeLogId;
        SELECT TotalRows = 0;
        RETURN;
    END;

    SELECT c.ChangeLogId, c.TableName, c.KeyText, c.ActionCode, c.BeforeJson, c.AfterJson,
           c.LoginName, c.ChangedOnUtc,
           ActorName = (SELECT TOP (1) u.DisplayName FROM sec.AppUser u WHERE u.LoginName = c.LoginName)
    FROM audit.ChangeLog c
    WHERE (@TableName  IS NULL OR c.TableName = @TableName)
      AND (@ActorLogin IS NULL OR c.LoginName = @ActorLogin)
      AND (@Search IS NULL OR c.KeyText LIKE N'%' + @Search + N'%'
           OR c.TableName LIKE N'%' + @Search + N'%' OR c.ActionCode LIKE N'%' + @Search + N'%')
    ORDER BY c.ChangedOnUtc DESC, c.ChangeLogId DESC
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT TotalRows = COUNT(*)
    FROM audit.ChangeLog c
    WHERE (@TableName  IS NULL OR c.TableName = @TableName)
      AND (@ActorLogin IS NULL OR c.LoginName = @ActorLogin)
      AND (@Search IS NULL OR c.KeyText LIKE N'%' + @Search + N'%'
           OR c.TableName LIKE N'%' + @Search + N'%' OR c.ActionCode LIKE N'%' + @Search + N'%');

    SELECT TableName, Changes = COUNT(*)
    FROM audit.ChangeLog GROUP BY TableName ORDER BY COUNT(*) DESC;
END
GO
PRINT '  audit.usp_ChangeLog_List          applied';
GO

PRINT '== 01_config_engine (contract) complete ==============================';
GO
