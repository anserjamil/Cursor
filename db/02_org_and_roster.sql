/* =====================================================================================
   02_org_and_roster.sql  —  the organisation tree, the roster, and the table mapping
   -------------------------------------------------------------------------------------
   The customer's operational tables sit in DB02.dbo alongside these schemas.  Nothing
   here assumes their column names: sel.TableMapping records where each source lives and
   sel.RosterField records what was discovered in it.  If a real table or column name
   differs, the mapping row changes — never the code.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 02_org_and_roster =================================================';
GO

/* --- sel.OrgNode ---------------------------------------------------------------
   ~2,942 units, eight levels deep.                                                */
IF OBJECT_ID('sel.OrgNode') IS NULL
BEGIN
    CREATE TABLE sel.OrgNode
    (
        OrgNodeId     int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_OrgNode PRIMARY KEY,
        OrgCode       nvarchar(40)  NOT NULL CONSTRAINT UQ_sel_OrgNode_Code UNIQUE,
        Name          nvarchar(200) NOT NULL,
        ParentOrgCode nvarchar(40)  NULL,
        OrgLevel      tinyint       NOT NULL CONSTRAINT DF_sel_OrgNode_Level  DEFAULT (1),
        IsActive      bit           NOT NULL CONSTRAINT DF_sel_OrgNode_Active DEFAULT (1)
    );
    CREATE INDEX IX_sel_OrgNode_Parent ON sel.OrgNode (ParentOrgCode) INCLUDE (OrgCode, Name, OrgLevel);
    PRINT '  sel.OrgNode                       created';
END
ELSE PRINT '  sel.OrgNode                       skipped';
GO

/* --- sel.OrgAncestor ------------------------------------------------------------
   The closure table.  A grant on a node reaches every descendant, and row-level
   security joins through this rather than walking the tree per row.                */
IF OBJECT_ID('sel.OrgAncestor') IS NULL
BEGIN
    CREATE TABLE sel.OrgAncestor
    (
        OrgCode         nvarchar(40) NOT NULL,   -- the descendant
        AncestorOrgCode nvarchar(40) NOT NULL,   -- itself, its parent, ... up to the root
        Depth           tinyint      NOT NULL,   -- 0 = itself
        CONSTRAINT PK_sel_OrgAncestor PRIMARY KEY (AncestorOrgCode, OrgCode)
    );
    CREATE INDEX IX_sel_OrgAncestor_Desc ON sel.OrgAncestor (OrgCode) INCLUDE (AncestorOrgCode, Depth);
    PRINT '  sel.OrgAncestor                   created';
END
ELSE PRINT '  sel.OrgAncestor                   skipped';
GO

/* --- sel.Employee ---------------------------------------------------------------
   The application's normalised core of the ~200-column roster record.  The long tail
   of columns is NOT mirrored here: it stays in the mapped roster table and is reached
   through sel.RosterField (criteria) and sel.ColumnCatalog (column picker), so adding
   a roster column never needs a migration.                                          */
IF OBJECT_ID('sel.Employee') IS NULL
BEGIN
    CREATE TABLE sel.Employee
    (
        PersonnelNo         nvarchar(30)  NOT NULL CONSTRAINT PK_sel_Employee PRIMARY KEY,
        FullName            nvarchar(200) NOT NULL,
        OrgCode             nvarchar(40)  NOT NULL,
        JobTitle            nvarchar(200) NULL,
        PermJobSuffix       nvarchar(30)  NULL,
        PermJobSuffixDesc   nvarchar(200) NULL,
        CurrentJobSuffix    nvarchar(30)  NULL,
        GradeCode           nvarchar(20)  NULL,
        ManagementLevelCode nvarchar(40)  NULL,
        IsActive            bit           NOT NULL CONSTRAINT DF_sel_Employee_Active DEFAULT (1),
        PermChiefInd        bit           NOT NULL CONSTRAINT DF_sel_Employee_Chief  DEFAULT (0),
        HireDate            date          NULL,
        PromotionDate       date          NULL,
        BirthDate           date          NULL,
        Gender              nvarchar(20)  NULL,
        Nationality         nvarchar(60)  NULL,
        Email               nvarchar(200) NULL,
        LoadedOnUtc         datetime2(3)  NOT NULL CONSTRAINT DF_sel_Employee_Loaded DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_sel_Employee_Org    ON sel.Employee (OrgCode, IsActive) INCLUDE (FullName, PermJobSuffix, GradeCode);
    CREATE INDEX IX_sel_Employee_Suffix ON sel.Employee (PermJobSuffix, IsActive) INCLUDE (PersonnelNo, OrgCode);
    CREATE INDEX IX_sel_Employee_Name   ON sel.Employee (FullName);
    PRINT '  sel.Employee                      created';
END
ELSE PRINT '  sel.Employee                      skipped';
GO

/* --- stg.Employee ---------------------------------------------------------------
   Staging: the roster lands here first so a row that cannot resolve its organisation
   becomes a visible load exception rather than a silently missing person.           */
IF OBJECT_ID('stg.Employee') IS NULL
BEGIN
    CREATE TABLE stg.Employee
    (
        StageId             bigint        IDENTITY(1,1) NOT NULL CONSTRAINT PK_stg_Employee PRIMARY KEY,
        PersonnelNo         nvarchar(30)  NULL,
        FullName            nvarchar(200) NULL,
        OrgCode             nvarchar(40)  NULL,
        JobTitle            nvarchar(200) NULL,
        PermJobSuffix       nvarchar(30)  NULL,
        PermJobSuffixDesc   nvarchar(200) NULL,
        CurrentJobSuffix    nvarchar(30)  NULL,
        GradeCode           nvarchar(20)  NULL,
        ManagementLevelCode nvarchar(40)  NULL,
        ActiveInd           nvarchar(20)  NULL,
        PermChiefInd        nvarchar(10)  NULL,
        HireDate            date          NULL,
        PromotionDate       date          NULL,
        BirthDate           date          NULL,
        Gender              nvarchar(20)  NULL,
        Nationality         nvarchar(60)  NULL,
        Email               nvarchar(200) NULL,
        BatchId             uniqueidentifier NOT NULL,
        LoadedOnUtc         datetime2(3)  NOT NULL CONSTRAINT DF_stg_Employee_Loaded DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_stg_Employee_Batch ON stg.Employee (BatchId) INCLUDE (PersonnelNo, OrgCode);
    PRINT '  stg.Employee                      created';
END
ELSE PRINT '  stg.Employee                      skipped';
GO

/* --- stg.LoadException ----------------------------------------------------------
   The difference between a wrong number somebody catches and a wrong number nobody
   does.  Every unmatched row lands here with the reason in words.                   */
IF OBJECT_ID('stg.LoadException') IS NULL
BEGIN
    CREATE TABLE stg.LoadException
    (
        LoadExceptionId bigint         IDENTITY(1,1) NOT NULL CONSTRAINT PK_stg_LoadException PRIMARY KEY,
        SourceKey       nvarchar(40)   NOT NULL,   -- ROSTER, COURSE, ASSESSMENT, ...
        SourceTable     nvarchar(260)  NULL,
        KeyText         nvarchar(200)  NULL,       -- the personnel number or item code that failed
        ReasonCode      nvarchar(60)   NOT NULL,
        ReasonText      nvarchar(600)  NOT NULL,   -- always a sentence
        RawJson         nvarchar(max)  NULL,
        BatchId         uniqueidentifier NULL,
        IsResolved      bit            NOT NULL CONSTRAINT DF_stg_LoadException_Resolved DEFAULT (0),
        ResolvedOnUtc   datetime2(3)   NULL,
        ResolvedByLogin nvarchar(128)  NULL,
        CreatedOnUtc    datetime2(3)   NOT NULL CONSTRAINT DF_stg_LoadException_On DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_stg_LoadException_Src ON stg.LoadException (SourceKey, IsResolved, CreatedOnUtc DESC);
    PRINT '  stg.LoadException                 created';
END
ELSE PRINT '  stg.LoadException                 skipped';
GO

/* --- sel.PersonAlias ------------------------------------------------------------
   When a source's EmployeeId is not the roster's PersonnelNo, map through here.
   Never fuzzy-match on a name.                                                     */
IF OBJECT_ID('sel.PersonAlias') IS NULL
BEGIN
    CREATE TABLE sel.PersonAlias
    (
        PersonAliasId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_PersonAlias PRIMARY KEY,
        SourceKey     nvarchar(40)  NOT NULL,      -- which source the alias belongs to, or ALL
        AliasKey      nvarchar(60)  NOT NULL,      -- the identifier that source uses
        PersonnelNo   nvarchar(30)  NOT NULL,
        Note          nvarchar(400) NULL,
        CONSTRAINT UQ_sel_PersonAlias UNIQUE (SourceKey, AliasKey)
    );
    CREATE INDEX IX_sel_PersonAlias_Person ON sel.PersonAlias (PersonnelNo);
    PRINT '  sel.PersonAlias                   created';
END
ELSE PRINT '  sel.PersonAlias                   skipped';
GO

/* --- sel.RosterField ------------------------------------------------------------
   Every roster column, discovered switched off.  "Enabled" means usable in criteria;
   "sensitive" means readable on a profile and refused as a filter.  The two are
   different questions and the screen must say so.                                   */
IF OBJECT_ID('sel.RosterField') IS NULL
BEGIN
    CREATE TABLE sel.RosterField
    (
        RosterFieldId  int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_RosterField PRIMARY KEY,
        FieldName      nvarchar(128) NOT NULL CONSTRAINT UQ_sel_RosterField_Name UNIQUE,
        Caption        nvarchar(160) NOT NULL,
        DataType       nvarchar(20)  NOT NULL,      -- text | number | date | bit
        SqlType        nvarchar(60)  NULL,          -- as reported by INFORMATION_SCHEMA
        /* ROSTER = a column of the mapped roster table; METRIC = a derived per-person
           figure from sel.EmployeeMetric.  Both are filterable; they are read differently. */
        SourceKind     nvarchar(20)  NOT NULL CONSTRAINT DF_sel_RosterField_Src DEFAULT (N'ROSTER'),
        IsEnabled      bit           NOT NULL CONSTRAINT DF_sel_RosterField_Enabled   DEFAULT (0),
        IsSensitive    bit           NOT NULL CONSTRAINT DF_sel_RosterField_Sensitive DEFAULT (0),
        GroupName      nvarchar(80)  NULL,
        SortOrder      int           NOT NULL CONSTRAINT DF_sel_RosterField_Sort      DEFAULT (0),
        UsageCount     int           NOT NULL CONSTRAINT DF_sel_RosterField_Usage     DEFAULT (0),
        DiscoveredOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sel_RosterField_Disc      DEFAULT (SYSUTCDATETIME()),
        LastSeenOnUtc  datetime2(3)  NULL,
        IsPresent      bit           NOT NULL CONSTRAINT DF_sel_RosterField_Present   DEFAULT (1)
    );
    PRINT '  sel.RosterField                   created';
END
ELSE PRINT '  sel.RosterField                   skipped';
GO

/* --- sel.TableMapping -----------------------------------------------------------
   Every table the application reads is named here.  A missing source is never a
   silent zero: IsMapped = 0 and every dependent requirement says, in words, that it
   can never be met.                                                                 */
IF OBJECT_ID('sel.TableMapping') IS NULL
BEGIN
    CREATE TABLE sel.TableMapping
    (
        TableMappingId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_TableMapping PRIMARY KEY,
        SourceKey      nvarchar(40)  NOT NULL CONSTRAINT UQ_sel_TableMapping_Key UNIQUE,
        Caption        nvarchar(160) NOT NULL,
        SchemaName     nvarchar(128) NOT NULL CONSTRAINT DF_sel_TableMapping_Schema DEFAULT (N'dbo'),
        TableName      nvarchar(128) NOT NULL,
        KeyColumn      nvarchar(128) NULL,          -- the person key
        ItemColumn     nvarchar(128) NULL,          -- the item / code column, where there is one
        ReadBy         nvarchar(400) NULL,          -- what reads it, in words
        BreaksWhenUnmapped nvarchar(600) NULL,      -- what breaks if it is absent, in words
        IsMapped       bit           NOT NULL CONSTRAINT DF_sel_TableMapping_Mapped DEFAULT (0),
        IsRequired     bit           NOT NULL CONSTRAINT DF_sel_TableMapping_Req    DEFAULT (0),
        RowCountCached bigint        NULL,
        LastSyncUtc    datetime2(3)  NULL,
        LastCheckedUtc datetime2(3)  NULL,
        SortOrder      int           NOT NULL CONSTRAINT DF_sel_TableMapping_Sort   DEFAULT (0)
    );
    PRINT '  sel.TableMapping                  created';
END
ELSE PRINT '  sel.TableMapping                  skipped';
GO

/* --- sel.TableMappingColumn -----------------------------------------------------
   The result of the INFORMATION_SCHEMA discovery, per mapped table.                 */
IF OBJECT_ID('sel.TableMappingColumn') IS NULL
BEGIN
    CREATE TABLE sel.TableMappingColumn
    (
        TableMappingColumnId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_TableMappingColumn PRIMARY KEY,
        TableMappingId int           NOT NULL CONSTRAINT FK_sel_TMC_Mapping REFERENCES sel.TableMapping(TableMappingId),
        ColumnName     nvarchar(128) NOT NULL,
        SqlType        nvarchar(60)  NOT NULL,
        DataType       nvarchar(20)  NOT NULL,     -- text | number | date | bit
        IsNullable     bit           NOT NULL,
        OrdinalPos     int           NOT NULL,
        DiscoveredOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sel_TMC_Disc DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_TMC UNIQUE (TableMappingId, ColumnName)
    );
    PRINT '  sel.TableMappingColumn            created';
END
ELSE PRINT '  sel.TableMappingColumn            skipped';
GO

/* =====================================================================================
   Functions and procedures
   ===================================================================================== */

/* sel.fn_MappedObject — the two-part name of a mapped source, or NULL when it is not
   mapped.  Dynamic SQL quotes this; nothing concatenates a table name by hand.       */
CREATE OR ALTER FUNCTION sel.fn_MappedObject (@SourceKey nvarchar(40))
RETURNS nvarchar(300)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @n nvarchar(300);
    SELECT @n = QUOTENAME(SchemaName) + N'.' + QUOTENAME(TableName)
    FROM sel.TableMapping
    WHERE SourceKey = @SourceKey AND IsMapped = 1;
    RETURN @n;
END
GO
PRINT '  sel.fn_MappedObject               applied';
GO

/* sel.fn_SqlTypeToDataType — one place that decides what a SQL type means to the
   criteria builder.  Five call sites would be five different answers.               */
CREATE OR ALTER FUNCTION sel.fn_SqlTypeToDataType (@SqlType nvarchar(60))
RETURNS nvarchar(20)
AS
BEGIN
    DECLARE @t nvarchar(60) = LOWER(LTRIM(RTRIM(ISNULL(@SqlType, N''))));
    RETURN CASE
        WHEN @t IN (N'bit')                                                              THEN N'bit'
        WHEN @t IN (N'date', N'datetime', N'datetime2', N'smalldatetime', N'datetimeoffset') THEN N'date'
        WHEN @t IN (N'tinyint', N'smallint', N'int', N'bigint', N'decimal', N'numeric',
                    N'float', N'real', N'money', N'smallmoney')                          THEN N'number'
        ELSE N'text'
    END;
END
GO
PRINT '  sel.fn_SqlTypeToDataType          applied';
GO

/* sel.usp_Org_RebuildAncestors — referenced by the roster load.  Rebuilds the closure
   from sel.OrgNode in one set-based statement, never a cursor per node.              */
CREATE OR ALTER PROCEDURE sel.usp_Org_RebuildAncestors
    @LoginName nvarchar(128) = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF NOT EXISTS (SELECT 1 FROM sel.OrgNode)
    BEGIN
        SET @Problem = N'There are no organisational units to build a tree from. Load the roster first.';
        SELECT TOP (0) CAST(NULL AS nvarchar(40)) AS OrgCode;
        RETURN;
    END;

    BEGIN TRAN;

    /* Depth first from each node up to the root, set-based. */
    WITH walk AS
    (
        SELECT n.OrgCode, AncestorOrgCode = n.OrgCode, Depth = CAST(0 AS tinyint), n.ParentOrgCode
        FROM sel.OrgNode n
        UNION ALL
        SELECT w.OrgCode, AncestorOrgCode = p.OrgCode, Depth = CAST(w.Depth + 1 AS tinyint), p.ParentOrgCode
        FROM walk w
        JOIN sel.OrgNode p ON p.OrgCode = w.ParentOrgCode
        WHERE w.Depth < 32                    -- a cycle in the source data must not spin for ever
    )
    SELECT OrgCode, AncestorOrgCode, Depth
    INTO #anc
    FROM walk
    OPTION (MAXRECURSION 32);

    TRUNCATE TABLE sel.OrgAncestor;
    INSERT sel.OrgAncestor (OrgCode, AncestorOrgCode, Depth)
    SELECT OrgCode, AncestorOrgCode, MIN(Depth)
    FROM #anc GROUP BY OrgCode, AncestorOrgCode;

    /* Depth 0 is the node itself, so its level is the count of its strict ancestors. */
    UPDATE n
       SET OrgLevel = CAST(x.Lvl AS tinyint)
    FROM sel.OrgNode n
    JOIN (SELECT OrgCode, Lvl = COUNT(*) FROM sel.OrgAncestor GROUP BY OrgCode) x
      ON x.OrgCode = n.OrgCode;

    COMMIT;
    DROP TABLE #anc;

    DECLARE @actor nvarchar(128) = ISNULL(@LoginName, N'system');
    EXEC audit.usp_Log @TableName = N'sel.OrgAncestor', @KeyText = N'(all)',
                       @ActionCode = N'REBUILD', @LoginName = @actor;

    SELECT Nodes = (SELECT COUNT(*) FROM sel.OrgNode),
           Edges = (SELECT COUNT(*) FROM sel.OrgAncestor),
           MaxLevel = (SELECT MAX(OrgLevel) FROM sel.OrgNode);
END
GO
PRINT '  sel.usp_Org_RebuildAncestors      applied';
GO

/* sel.usp_Org_Tree — the Row-level security screen's tree, with headcount per node
   and whether a named viewer is granted it.                                          */
CREATE OR ALTER PROCEDURE sel.usp_Org_Tree
    @LoginName      nvarchar(128),
    @CompareLogin   nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT n.OrgNodeId, n.OrgCode, n.Name, n.ParentOrgCode, n.OrgLevel, n.IsActive,
           HeadCount = (SELECT COUNT(*) FROM sel.Employee e
                        JOIN sel.OrgAncestor a ON a.OrgCode = e.OrgCode
                        WHERE a.AncestorOrgCode = n.OrgCode AND e.IsActive = 1),
           IsGranted = CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@LoginName) s
                                          WHERE s.OrgCode = n.OrgCode) THEN 1 ELSE 0 END),
           IsGrantedCompare = CONVERT(bit, CASE WHEN @CompareLogin IS NULL THEN NULL
                                   WHEN EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@CompareLogin) s
                                                 WHERE s.OrgCode = n.OrgCode) THEN 1 ELSE 0 END)
    FROM sel.OrgNode n
    ORDER BY n.OrgLevel, n.Name;
END
GO
PRINT '  sel.usp_Org_Tree                  applied';
GO

/* sel.usp_TableMapping_Discover — the first action of a build.  Runs over
   INFORMATION_SCHEMA.COLUMNS for every source the application names and records what
   is really there.  Do not assume the column list.                                   */
CREATE OR ALTER PROCEDURE sel.usp_TableMapping_Discover
    @LoginName nvarchar(128),
    @SourceKey nvarchar(40) = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(40)) AS SourceKey;
        RETURN;
    END;

    BEGIN TRAN;

    /* Which of the named tables actually exist right now. */
    UPDATE m
       SET IsMapped = CONVERT(bit, CASE WHEN t.TABLE_NAME IS NULL THEN 0 ELSE 1 END),
           LastCheckedUtc = SYSUTCDATETIME()
    FROM sel.TableMapping m
    LEFT JOIN INFORMATION_SCHEMA.TABLES t
           ON t.TABLE_SCHEMA = m.SchemaName AND t.TABLE_NAME = m.TableName
    WHERE (@SourceKey IS NULL OR m.SourceKey = @SourceKey);

    /* Drop the columns of tables that are no longer there, then re-discover. */
    DELETE c
    FROM sel.TableMappingColumn c
    JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
    WHERE (@SourceKey IS NULL OR m.SourceKey = @SourceKey);

    INSERT sel.TableMappingColumn (TableMappingId, ColumnName, SqlType, DataType, IsNullable, OrdinalPos)
    SELECT m.TableMappingId,
           c.COLUMN_NAME,
           c.DATA_TYPE,
           sel.fn_SqlTypeToDataType(c.DATA_TYPE),
           CASE WHEN c.IS_NULLABLE = 'YES' THEN 1 ELSE 0 END,
           c.ORDINAL_POSITION
    FROM sel.TableMapping m
    JOIN INFORMATION_SCHEMA.COLUMNS c
      ON c.TABLE_SCHEMA = m.SchemaName AND c.TABLE_NAME = m.TableName
    WHERE m.IsMapped = 1
      AND (@SourceKey IS NULL OR m.SourceKey = @SourceKey);

    COMMIT;

    EXEC audit.usp_Log @TableName = N'sel.TableMapping', @KeyText = @SourceKey,
                       @ActionCode = N'DISCOVER', @LoginName = @LoginName;

    EXEC sel.usp_TableMapping_List @LoginName = @LoginName;
END
GO
PRINT '  sel.usp_TableMapping_Discover     applied';
GO

/* sel.usp_TableMapping_List — the Table mapping screen. */
CREATE OR ALTER PROCEDURE sel.usp_TableMapping_List
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT m.TableMappingId, m.SourceKey, m.Caption, m.SchemaName, m.TableName,
           m.KeyColumn, m.ItemColumn, m.ReadBy, m.BreaksWhenUnmapped,
           m.IsMapped, m.IsRequired, m.RowCountCached, m.LastSyncUtc, m.LastCheckedUtc, m.SortOrder,
           ColumnCount = (SELECT COUNT(*) FROM sel.TableMappingColumn c WHERE c.TableMappingId = m.TableMappingId),
           /* The key column must actually be present, or every list empties at once. */
           KeyColumnPresent = CONVERT(bit, CASE
                WHEN m.KeyColumn IS NULL THEN NULL
                WHEN EXISTS (SELECT 1 FROM sel.TableMappingColumn c
                             WHERE c.TableMappingId = m.TableMappingId AND c.ColumnName = m.KeyColumn) THEN 1
                ELSE 0 END),
           ItemColumnPresent = CONVERT(bit, CASE
                WHEN m.ItemColumn IS NULL THEN NULL
                WHEN EXISTS (SELECT 1 FROM sel.TableMappingColumn c
                             WHERE c.TableMappingId = m.TableMappingId AND c.ColumnName = m.ItemColumn) THEN 1
                ELSE 0 END)
    FROM sel.TableMapping m
    ORDER BY m.SortOrder, m.Caption;

    SELECT c.TableMappingColumnId, c.TableMappingId, m.SourceKey, c.ColumnName, c.SqlType,
           c.DataType, c.IsNullable, c.OrdinalPos
    FROM sel.TableMappingColumn c
    JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
    ORDER BY m.SortOrder, c.OrdinalPos;
END
GO
PRINT '  sel.usp_TableMapping_List         applied';
GO

/* sel.usp_TableMapping_Save — change the mapping row, never the code. */
CREATE OR ALTER PROCEDURE sel.usp_TableMapping_Save
    @LoginName  nvarchar(128),
    @SourceKey  nvarchar(40),
    @SchemaName nvarchar(128),
    @TableName  nvarchar(128),
    @KeyColumn  nvarchar(128) = NULL,
    @ItemColumn nvarchar(128) = NULL,
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS TableMappingId;
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM sel.TableMapping WHERE SourceKey = @SourceKey)
    BEGIN
        SET @Problem = N'There is no source called ' + @SourceKey + N' to map.';
        SELECT TOP (0) CAST(NULL AS int) AS TableMappingId;
        RETURN;
    END;

    DECLARE @before nvarchar(max) =
        (SELECT SourceKey, SchemaName, TableName, KeyColumn, ItemColumn, IsMapped
         FROM sel.TableMapping WHERE SourceKey = @SourceKey FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    UPDATE sel.TableMapping
       SET SchemaName = @SchemaName,
           TableName  = @TableName,
           KeyColumn  = @KeyColumn,
           ItemColumn = @ItemColumn
    WHERE SourceKey = @SourceKey;

    DECLARE @after nvarchar(max) =
        (SELECT SourceKey, SchemaName, TableName, KeyColumn, ItemColumn, IsMapped
         FROM sel.TableMapping WHERE SourceKey = @SourceKey FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    EXEC audit.usp_Log @TableName = N'sel.TableMapping', @KeyText = @SourceKey, @ActionCode = N'UPDATE',
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    /* Re-discover straight away so the screen never shows a stale column list. */
    DECLARE @p nvarchar(400);
    EXEC sel.usp_TableMapping_Discover @LoginName = @LoginName, @SourceKey = @SourceKey, @Problem = @p OUTPUT;
END
GO
PRINT '  sel.usp_TableMapping_Save         applied';
GO

/* sel.usp_LoadException_List — /Admin/LoadExceptions. */
CREATE OR ALTER PROCEDURE sel.usp_LoadException_List
    @LoginName   nvarchar(128),
    @SourceKey   nvarchar(40) = NULL,
    @IncludeResolved bit = 0,
    @Search      nvarchar(200) = NULL,
    @PageNo      int = 1,
    @PageSize    int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageNo   IS NULL OR @PageNo < 1 SET @PageNo = 1;

    ;WITH x AS
    (
        SELECT e.*
        FROM stg.LoadException e
        WHERE (@SourceKey IS NULL OR e.SourceKey = @SourceKey)
          AND (@IncludeResolved = 1 OR e.IsResolved = 0)
          AND (@Search IS NULL OR e.KeyText LIKE N'%' + @Search + N'%' OR e.ReasonText LIKE N'%' + @Search + N'%')
    )
    SELECT LoadExceptionId, SourceKey, SourceTable, KeyText, ReasonCode, ReasonText,
           BatchId, IsResolved, ResolvedOnUtc, ResolvedByLogin, CreatedOnUtc
    FROM x
    ORDER BY CreatedOnUtc DESC, LoadExceptionId DESC
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT TotalRows = COUNT(*)
    FROM stg.LoadException e
    WHERE (@SourceKey IS NULL OR e.SourceKey = @SourceKey)
      AND (@IncludeResolved = 1 OR e.IsResolved = 0)
      AND (@Search IS NULL OR e.KeyText LIKE N'%' + @Search + N'%' OR e.ReasonText LIKE N'%' + @Search + N'%');

    SELECT SourceKey, Unresolved = COUNT(*)
    FROM stg.LoadException WHERE IsResolved = 0
    GROUP BY SourceKey ORDER BY COUNT(*) DESC;
END
GO
PRINT '  sel.usp_LoadException_List        applied';
GO

/* sel.usp_RosterField_List — the Roster fields screen. */
CREATE OR ALTER PROCEDURE sel.usp_RosterField_List
    @LoginName   nvarchar(128),
    @Search      nvarchar(200) = NULL,
    @EnabledOnly bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RosterFieldId, FieldName, Caption, DataType, SqlType, SourceKind, IsEnabled, IsSensitive,
           GroupName, SortOrder, UsageCount, DiscoveredOnUtc, LastSeenOnUtc, IsPresent
    FROM sel.RosterField
    WHERE (@Search IS NULL OR FieldName LIKE N'%' + @Search + N'%' OR Caption LIKE N'%' + @Search + N'%')
      AND (@EnabledOnly = 0 OR IsEnabled = 1)
    ORDER BY CASE WHEN IsEnabled = 1 THEN 0 ELSE 1 END, SortOrder, Caption;

    SELECT TotalFields   = COUNT(*),
           EnabledCount  = SUM(CASE WHEN IsEnabled  = 1 THEN 1 ELSE 0 END),
           SensitiveCount= SUM(CASE WHEN IsSensitive= 1 THEN 1 ELSE 0 END),
           MissingCount  = SUM(CASE WHEN IsPresent  = 0 THEN 1 ELSE 0 END)
    FROM sel.RosterField;
END
GO
PRINT '  sel.usp_RosterField_List          applied';
GO

PRINT '== 02_org_and_roster complete ========================================';
GO
