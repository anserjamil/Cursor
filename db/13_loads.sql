/* =====================================================================================
   13_loads.sql  —  bringing the source tables in
   -------------------------------------------------------------------------------------
   Every load reads through sel.TableMapping, so a table or column that is named
   differently in the real database is a mapping change, never a code change.  The column
   names inside the roster are settings for the same reason.

   The two things that will actually go wrong, and what is done about them:

     * Personnel-number mismatch.  If a source's EmployeeId is not the roster's
       PersonnelNo, it is mapped through sel.PersonAlias.  Nothing here ever fuzzy-matches
       on a name.
     * Item codes not in the catalogue.  CRS-CAP-02 matches nothing if the extract says
       CAP02.  Codes are normalised on the way in, unknown ones are upserted into
       sel.CatalogItem with NeedsReview = 1, and every unmatched row is written to
       stg.LoadException.

   A missing source is never a silent zero: it is a refusal with a sentence.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 13_loads ==========================================================';
GO

/* The roster's own column names.  Defaults match the prototype; if the real column is
   called something else, change the setting rather than the procedure.                */
MERGE cfg.Setting AS t
USING (VALUES
    (N'ROSTER_COL_NAME',         N'EmployeeName',       N'The roster column holding the person''s name.'),
    (N'ROSTER_COL_ORG',          N'OrgCode',            N'The roster column holding the organisation code.'),
    (N'ROSTER_COL_ORG_NAME',     N'OrgName',            N'The roster column holding the organisation name.'),
    (N'ROSTER_COL_ORG_PARENT',   N'ParentOrgCode',      N'The roster column holding the parent organisation code.'),
    (N'ROSTER_COL_JOBTITLE',     N'JobTitle',           N'The roster column holding the job title.'),
    (N'ROSTER_COL_SUFFIX',       N'PermJobSuffix',      N'The roster column holding the permanent job suffix.'),
    (N'ROSTER_COL_SUFFIXDESC',   N'PermJobSuffixDesc',  N'The roster column describing the permanent job suffix.'),
    (N'ROSTER_COL_CURRENT_SUFFIX', N'CurrentJobSuffix', N'The roster column holding the current job suffix.'),
    (N'ROSTER_COL_GRADE',        N'GradeCode',          N'The roster column holding the grade.'),
    (N'ROSTER_COL_MGMTLEVEL',    N'ManagementLevel',    N'The roster column holding the management level.'),
    (N'ROSTER_COL_ACTIVE',       N'ActiveInd',          N'The roster column saying whether the person is active.'),
    (N'ROSTER_COL_CHIEF',        N'PermChiefInd',       N'The roster column marking a chief position.'),
    (N'ROSTER_COL_HIREDATE',     N'HireDate',           N'The roster column holding the hire date.'),
    (N'ROSTER_COL_PROMODATE',    N'PromotionDate',      N'The roster column holding the last promotion date.'),
    (N'ROSTER_COL_BIRTHDATE',    N'BirthDate',          N'The roster column holding the date of birth.'),
    (N'ROSTER_COL_GENDER',       N'Gender',             N'The roster column holding gender.'),
    (N'ROSTER_COL_NATIONALITY',  N'Nationality',        N'The roster column holding nationality.'),
    (N'ROSTER_COL_EMAIL',        N'Email',              N'The roster column holding the email address.')
) AS s (SettingKey, TextValue, Description)
   ON t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Description = s.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SettingKey, TextValue, Description) VALUES (s.SettingKey, s.TextValue, s.Description);
PRINT '  cfg.Setting (roster columns)      seeded';
GO

/* Columns the prototype treats as sensitive: readable on a record, refused as a filter. */
MERGE cfg.Setting AS t
USING (VALUES (N'SENSITIVE_COLUMNS', N'Gender,Nationality,BirthDate,DateOfBirth,SpecialNeedInd,MaritalStatus',
               N'Roster columns that are readable on a person''s record but never usable as a filter.'))
    AS s (SettingKey, TextValue, Description)
   ON t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Description = s.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SettingKey, TextValue, Description) VALUES (s.SettingKey, s.TextValue, s.Description);
PRINT '  cfg.Setting (sensitive columns)   seeded';
GO

/* sel.fn_RosterColumn — the real name of a roster column, or NULL when the mapped table
   does not have one by that name.  A load that names a column the table has not got
   would otherwise fail with a SQL error instead of a sentence.                        */
CREATE OR ALTER FUNCTION sel.fn_RosterColumn (@SettingKey nvarchar(80))
RETURNS nvarchar(128)
AS
BEGIN
    DECLARE @col nvarchar(128) = cfg.fn_SettingText(@SettingKey);
    IF @col IS NULL RETURN NULL;
    IF NOT EXISTS (SELECT 1 FROM sel.TableMappingColumn c
                   JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
                   WHERE m.SourceKey = N'ROSTER' AND c.ColumnName = @col)
        RETURN NULL;
    RETURN @col;
END
GO
PRINT '  sel.fn_RosterColumn               applied';
GO

/* sel.fn_ColumnOrNull — a column expression, or a typed NULL when the column is absent.
   One helper, so every load reads an optional column the same way.                    */
CREATE OR ALTER FUNCTION sel.fn_ColumnOrNull (@Alias nvarchar(20), @ColumnName nvarchar(128), @SqlType nvarchar(60))
RETURNS nvarchar(300)
AS
BEGIN
    IF @ColumnName IS NULL RETURN N'CAST(NULL AS ' + @SqlType + N')';
    RETURN N'TRY_CONVERT(' + @SqlType + N', ' + @Alias + N'.' + QUOTENAME(@ColumnName) + N')';
END
GO
PRINT '  sel.fn_ColumnOrNull               applied';
GO

/* =====================================================================================
   sel.usp_Roster_Load — roster -> stg.Employee -> sel.Employee
   -------------------------------------------------------------------------------------
   A row whose organisation does not resolve in sel.OrgNode becomes a load exception
   rather than a person nobody can see.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Roster_Load
    @LoginName nvarchar(128),
    @AsOf      date = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    IF sec.fn_ScreenAccess(@LoginName, N'/Admin/Policy/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS Loaded; RETURN;
    END;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'ROSTER');
    DECLARE @keyCol nvarchar(128) = (SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'ROSTER');
    IF @obj IS NULL OR @keyCol IS NULL
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS int) AS Loaded; RETURN;
    END;

    DECLARE @batch uniqueidentifier = NEWID();
    DECLARE @active nvarchar(400) = ISNULL(cfg.fn_SettingText(N'ROSTER_ACTIVE_VALUES'), N'Y');

    /* Every optional column resolves to itself or to a typed NULL, so a roster that is
       missing one still loads and the screen shows a blank rather than failing. */
    DECLARE @sql nvarchar(max) = N'
        INSERT stg.Employee (PersonnelNo, FullName, OrgCode, JobTitle, PermJobSuffix, PermJobSuffixDesc,
                             CurrentJobSuffix, GradeCode, ManagementLevelCode, ActiveInd, PermChiefInd,
                             HireDate, PromotionDate, BirthDate, Gender, Nationality, Email, BatchId)
        SELECT TRY_CONVERT(nvarchar(30),  rs.' + QUOTENAME(@keyCol) + N'),
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_NAME'),           N'nvarchar(200)') + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_ORG'),            N'nvarchar(40)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_JOBTITLE'),       N'nvarchar(200)') + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_SUFFIX'),         N'nvarchar(30)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_SUFFIXDESC'),     N'nvarchar(200)') + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_CURRENT_SUFFIX'), N'nvarchar(30)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_GRADE'),          N'nvarchar(20)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_MGMTLEVEL'),      N'nvarchar(40)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_ACTIVE'),         N'nvarchar(20)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_CHIEF'),          N'nvarchar(10)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_HIREDATE'),       N'date')          + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_PROMODATE'),      N'date')          + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_BIRTHDATE'),      N'date')          + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_GENDER'),         N'nvarchar(20)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_NATIONALITY'),    N'nvarchar(60)')  + N',
               ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_EMAIL'),          N'nvarchar(200)') + N',
               @batch
        FROM ' + @obj + N' rs;';

    BEGIN TRY
        TRUNCATE TABLE stg.Employee;
        EXEC sp_executesql @sql, N'@batch uniqueidentifier', @batch = @batch;
    END TRY
    BEGIN CATCH
        SET @Problem = N'The roster could not be read: ' + ERROR_MESSAGE();
        SELECT TOP (0) CAST(NULL AS int) AS Loaded; RETURN;
    END CATCH;

    /* The organisation tree, built from the roster's own org columns where it has them. */
    DECLARE @orgCol nvarchar(128) = sel.fn_RosterColumn(N'ROSTER_COL_ORG');
    IF @orgCol IS NOT NULL
    BEGIN
        DECLARE @orgSql nvarchar(max) = N'
            MERGE sel.OrgNode AS t
            USING (SELECT DISTINCT
                          OrgCode = TRY_CONVERT(nvarchar(40), rs.' + QUOTENAME(@orgCol) + N'),
                          Name    = ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_ORG_NAME'),   N'nvarchar(200)') + N',
                          Parent  = ' + sel.fn_ColumnOrNull(N'rs', sel.fn_RosterColumn(N'ROSTER_COL_ORG_PARENT'), N'nvarchar(40)')  + N'
                   FROM ' + @obj + N' rs
                   WHERE rs.' + QUOTENAME(@orgCol) + N' IS NOT NULL) AS s
               ON t.OrgCode = s.OrgCode
            WHEN MATCHED THEN UPDATE SET Name = ISNULL(s.Name, t.Name),
                                         ParentOrgCode = ISNULL(s.Parent, t.ParentOrgCode)
            WHEN NOT MATCHED BY TARGET THEN
                INSERT (OrgCode, Name, ParentOrgCode) VALUES (s.OrgCode, ISNULL(s.Name, s.OrgCode), s.Parent);';
        BEGIN TRY
            EXEC sp_executesql @orgSql;
        END TRY
        BEGIN CATCH
            INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
            VALUES (N'ROSTER', @obj, NULL, N'ORG_BUILD_FAILED',
                    N'The organisation tree could not be built from the roster: ' + ERROR_MESSAGE(), @batch);
        END CATCH;
    END;

    /* A parent that does not exist would orphan a whole subtree: record it and cut the
       link, rather than losing everyone under it. */
    INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
    SELECT N'ROSTER', @obj, n.OrgCode, N'ORG_PARENT_MISSING',
           N'Organisation ' + n.OrgCode + N' names a parent (' + n.ParentOrgCode
         + N') that is not in the roster, so it was treated as a root.', @batch
    FROM sel.OrgNode n
    WHERE n.ParentOrgCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM sel.OrgNode p WHERE p.OrgCode = n.ParentOrgCode);

    UPDATE n SET ParentOrgCode = NULL
    FROM sel.OrgNode n
    WHERE n.ParentOrgCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM sel.OrgNode p WHERE p.OrgCode = n.ParentOrgCode);

    DECLARE @p nvarchar(400);
    EXEC sel.usp_Org_RebuildAncestors @LoginName = @LoginName, @Problem = @p OUTPUT;

    /* Rows that cannot be placed.  Each one is a sentence, not a silent drop. */
    INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
    SELECT N'ROSTER', @obj, ISNULL(s.PersonnelNo, N'(no personnel number)'),
           CASE WHEN s.PersonnelNo IS NULL THEN N'NO_KEY' ELSE N'ORG_NOT_FOUND' END,
           CASE WHEN s.PersonnelNo IS NULL
                THEN N'A roster row has no personnel number, so it cannot be joined to anything.'
                ELSE N'Personnel number ' + s.PersonnelNo + N' names organisation '
                   + ISNULL(s.OrgCode, N'(none)') + N', which is not in the organisation tree.' END,
           @batch
    FROM stg.Employee s
    WHERE s.BatchId = @batch
      AND (s.PersonnelNo IS NULL
        OR s.OrgCode IS NULL
        OR NOT EXISTS (SELECT 1 FROM sel.OrgNode o WHERE o.OrgCode = s.OrgCode));

    BEGIN TRAN;
    MERGE sel.Employee AS t
    USING (SELECT s.PersonnelNo, s.FullName, s.OrgCode, s.JobTitle, s.PermJobSuffix, s.PermJobSuffixDesc,
                  s.CurrentJobSuffix, s.GradeCode, s.ManagementLevelCode,
                  IsActive = CONVERT(bit, CASE WHEN N',' + @active + N',' LIKE N'%,' + ISNULL(s.ActiveInd, N'') + N',%'
                                  THEN 1 ELSE 0 END),
                  PermChiefInd = CASE WHEN UPPER(ISNULL(s.PermChiefInd, N'')) IN (N'Y', N'1', N'TRUE')
                                      THEN 1 ELSE 0 END,
                  s.HireDate, s.PromotionDate, s.BirthDate, s.Gender, s.Nationality, s.Email
           FROM stg.Employee s
           WHERE s.BatchId = @batch AND s.PersonnelNo IS NOT NULL
             AND EXISTS (SELECT 1 FROM sel.OrgNode o WHERE o.OrgCode = s.OrgCode)) AS src
       ON t.PersonnelNo = src.PersonnelNo
    WHEN MATCHED THEN UPDATE SET
        FullName = ISNULL(src.FullName, t.FullName), OrgCode = src.OrgCode, JobTitle = src.JobTitle,
        PermJobSuffix = src.PermJobSuffix, PermJobSuffixDesc = src.PermJobSuffixDesc,
        CurrentJobSuffix = src.CurrentJobSuffix, GradeCode = src.GradeCode,
        ManagementLevelCode = src.ManagementLevelCode, IsActive = src.IsActive,
        PermChiefInd = src.PermChiefInd, HireDate = src.HireDate, PromotionDate = src.PromotionDate,
        BirthDate = src.BirthDate, Gender = src.Gender, Nationality = src.Nationality,
        Email = src.Email, LoadedOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, FullName, OrgCode, JobTitle, PermJobSuffix, PermJobSuffixDesc,
                CurrentJobSuffix, GradeCode, ManagementLevelCode, IsActive, PermChiefInd,
                HireDate, PromotionDate, BirthDate, Gender, Nationality, Email)
        VALUES (src.PersonnelNo, ISNULL(src.FullName, src.PersonnelNo), src.OrgCode, src.JobTitle,
                src.PermJobSuffix, src.PermJobSuffixDesc, src.CurrentJobSuffix, src.GradeCode,
                src.ManagementLevelCode, src.IsActive, src.PermChiefInd, src.HireDate,
                src.PromotionDate, src.BirthDate, src.Gender, src.Nationality, src.Email);
    DECLARE @loaded int = @@ROWCOUNT;
    COMMIT;

    /* Discover the roster's columns, then the fields and the column catalogue. */
    EXEC sel.usp_TableMapping_Discover @LoginName = @LoginName, @SourceKey = N'ROSTER', @Problem = @p OUTPUT;
    EXEC sel.usp_RosterField_Sync @LoginName = @LoginName, @Problem = @p OUTPUT;
    EXEC sel.usp_ColumnCatalog_Sync @LoginName = @LoginName, @Problem = @p OUTPUT;

    UPDATE sel.TableMapping SET LastSyncUtc = SYSUTCDATETIME(),
           RowCountCached = (SELECT COUNT(*) FROM stg.Employee WHERE BatchId = @batch)
    WHERE SourceKey = N'ROSTER';

    EXEC audit.usp_Log @TableName = N'sel.Employee', @KeyText = N'(roster load)', @ActionCode = N'LOAD',
                       @LoginName = @LoginName;

    SELECT Loaded = @loaded,
           StagedRows = (SELECT COUNT(*) FROM stg.Employee WHERE BatchId = @batch),
           Exceptions = (SELECT COUNT(*) FROM stg.LoadException WHERE BatchId = @batch),
           OrgNodes = (SELECT COUNT(*) FROM sel.OrgNode),
           BatchId = @batch;
END
GO
PRINT '  sel.usp_Roster_Load               applied';
GO

/* sel.usp_ColumnCatalog_Sync — the ~200-column employee record, grouped and searchable,
   behind the column picker.  Sensitive columns are marked from configuration.          */
CREATE OR ALTER PROCEDURE sel.usp_ColumnCatalog_Sync
    @LoginName nvarchar(128),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF NOT EXISTS (SELECT 1 FROM sel.TableMapping WHERE SourceKey = N'ROSTER' AND IsMapped = 1)
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS int) AS ColumnCatalogId; RETURN;
    END;

    DECLARE @sensitive nvarchar(400) = ISNULL(cfg.fn_SettingText(N'SENSITIVE_COLUMNS'), N'');
    DECLARE @defaults nvarchar(400) = ISNULL(cfg.fn_SettingText(N'ROSTER_COL_NAME'), N'')
                                    + N',' + ISNULL(cfg.fn_SettingText(N'ROSTER_COL_JOBTITLE'), N'')
                                    + N',' + ISNULL(cfg.fn_SettingText(N'ROSTER_COL_GRADE'), N'');

    UPDATE sel.ColumnCatalog SET IsPresent = 0;

    MERGE sel.ColumnCatalog AS t
    USING (SELECT c.ColumnName, c.DataType, c.OrdinalPos
           FROM sel.TableMappingColumn c
           JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
           WHERE m.SourceKey = N'ROSTER') AS s
       ON t.ColumnName = s.ColumnName
    WHEN MATCHED THEN UPDATE SET
        DataType = s.DataType, SortOrder = s.OrdinalPos, IsPresent = 1,
        IsSensitive = CONVERT(bit, CASE WHEN N',' + @sensitive + N',' LIKE N'%,' + s.ColumnName + N',%' THEN 1 ELSE 0 END)
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (ColumnName, Caption, GroupName, DataType, IsSensitive, IsDefault, SortOrder, IsPresent)
        VALUES (s.ColumnName, s.ColumnName,
                /* A rough grouping so the picker is not one flat list of two hundred. */
                CASE WHEN s.ColumnName LIKE N'%Org%'  OR s.ColumnName LIKE N'%Depart%' THEN N'Organisation'
                     WHEN s.ColumnName LIKE N'%Job%'  OR s.ColumnName LIKE N'%Position%'
                       OR s.ColumnName LIKE N'%Suffix%' OR s.ColumnName LIKE N'%Grade%' THEN N'Job'
                     WHEN s.ColumnName LIKE N'%Date%' OR s.ColumnName LIKE N'%Hire%'   THEN N'Dates'
                     WHEN s.ColumnName LIKE N'%Name%' OR s.ColumnName LIKE N'%Email%'  THEN N'Person'
                     ELSE N'Roster' END,
                s.DataType,
                CASE WHEN N',' + @sensitive + N',' LIKE N'%,' + s.ColumnName + N',%' THEN 1 ELSE 0 END,
                CASE WHEN N',' + @defaults  + N',' LIKE N'%,' + s.ColumnName + N',%' THEN 1 ELSE 0 END,
                s.OrdinalPos, 1);

    SELECT Columns = (SELECT COUNT(*) FROM sel.ColumnCatalog WHERE IsPresent = 1),
           Sensitive = (SELECT COUNT(*) FROM sel.ColumnCatalog WHERE IsPresent = 1 AND IsSensitive = 1),
           Missing = (SELECT COUNT(*) FROM sel.ColumnCatalog WHERE IsPresent = 0);
END
GO
PRINT '  sel.usp_ColumnCatalog_Sync        applied';
GO

/* =====================================================================================
   sel.usp_Evidence_SyncOne — one flag-mode source into sel.EmployeeRecord
   -------------------------------------------------------------------------------------
   MERGE on (PersonnelNo, KindCode, ItemCode).  Everything that could not be placed lands
   in stg.LoadException with a sentence.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Evidence_SyncOne
    @LoginName nvarchar(128),
    @SourceKey nvarchar(40),
    @KindCode  nvarchar(30),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(@SourceKey);
    IF @obj IS NULL
    BEGIN
        /* A missing source is never a silent zero. */
        SET @Problem = ISNULL((SELECT BreaksWhenUnmapped FROM sel.TableMapping WHERE SourceKey = @SourceKey),
                              N'No table is mapped for ' + @SourceKey + N'.');
        SELECT SourceKey = @SourceKey, Loaded = CAST(NULL AS int), Exceptions = CAST(NULL AS int), Problem = @Problem;
        RETURN;
    END;

    DECLARE @keyCol  nvarchar(128) = (SELECT KeyColumn  FROM sel.TableMapping WHERE SourceKey = @SourceKey);
    DECLARE @itemCol nvarchar(128) = (SELECT ItemColumn FROM sel.TableMapping WHERE SourceKey = @SourceKey);
    IF @keyCol IS NULL OR @itemCol IS NULL
    BEGIN
        SET @Problem = N'The mapping for ' + @SourceKey + N' does not name both a person column and an item column.';
        SELECT SourceKey = @SourceKey, Loaded = CAST(NULL AS int), Exceptions = CAST(NULL AS int), Problem = @Problem;
        RETURN;
    END;

    DECLARE @batch uniqueidentifier = NEWID();

    /* Land the source rows as they are, resolving the person key through the alias table
       where the source uses its own identifier.  Never fuzzy-match on a name. */
    CREATE TABLE #raw
    (
        SourceKeyText nvarchar(60)  NULL,
        PersonnelNo   nvarchar(30)  NULL,
        RawItemCode   nvarchar(120) NULL,
        ItemCode      nvarchar(60)  NULL,
        Status        nvarchar(60)  NULL,
        Score         decimal(18,4) NULL,
        MaxScore      decimal(18,4) NULL,
        CompletedOn   date          NULL,
        ExpiresOn     date          NULL
    );

    /* Optional columns resolve to typed NULLs when the source has not got them. */
    DECLARE @has nvarchar(max) = N'';
    DECLARE @statusExpr nvarchar(300) = N'CAST(NULL AS nvarchar(60))',
            @scoreExpr  nvarchar(300) = N'CAST(NULL AS decimal(18,4))',
            @maxExpr    nvarchar(300) = N'CAST(NULL AS decimal(18,4))',
            @compExpr   nvarchar(300) = N'CAST(NULL AS date)',
            @expExpr    nvarchar(300) = N'CAST(NULL AS date)';

    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = @SourceKey AND c.ColumnName = N'Status')
        SET @statusExpr = N'TRY_CONVERT(nvarchar(60), src.[Status])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = @SourceKey AND c.ColumnName = N'Score')
        SET @scoreExpr = N'TRY_CONVERT(decimal(18,4), src.[Score])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = @SourceKey AND c.ColumnName = N'MaxScore')
        SET @maxExpr = N'TRY_CONVERT(decimal(18,4), src.[MaxScore])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = @SourceKey AND c.ColumnName = N'CompletedOn')
        SET @compExpr = N'TRY_CONVERT(date, src.[CompletedOn])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = @SourceKey AND c.ColumnName = N'ExpiresOn')
        SET @expExpr = N'TRY_CONVERT(date, src.[ExpiresOn])';

    DECLARE @sql nvarchar(max) = N'
        INSERT #raw (SourceKeyText, PersonnelNo, RawItemCode, ItemCode, Status, Score, MaxScore, CompletedOn, ExpiresOn)
        SELECT SourceKeyText = TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@keyCol) + N'),
               /* The roster''s own number, or the one the alias table maps it to. */
               PersonnelNo = COALESCE(e.PersonnelNo, al.PersonnelNo),
               RawItemCode = TRY_CONVERT(nvarchar(120), src.' + QUOTENAME(@itemCol) + N'),
               /* Normalised on the way in: trimmed and upper-cased, so CAP02 and cap02
                  are the same code and only the dash is a real difference. */
               ItemCode = UPPER(LTRIM(RTRIM(TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@itemCol) + N')))),
               ' + @statusExpr + N', ' + @scoreExpr + N', ' + @maxExpr + N', ' + @compExpr + N', ' + @expExpr + N'
        FROM ' + @obj + N' src
        LEFT JOIN sel.Employee e ON e.PersonnelNo = TRY_CONVERT(nvarchar(30), src.' + QUOTENAME(@keyCol) + N')
        LEFT JOIN sel.PersonAlias al ON al.AliasKey = TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@keyCol) + N')
                                    AND al.SourceKey IN (@SourceKey, N''ALL'');';

    BEGIN TRY
        EXEC sp_executesql @sql, N'@SourceKey nvarchar(40)', @SourceKey = @SourceKey;
    END TRY
    BEGIN CATCH
        SET @Problem = @SourceKey + N' could not be read: ' + ERROR_MESSAGE();
        SELECT SourceKey = @SourceKey, Loaded = CAST(NULL AS int), Exceptions = CAST(NULL AS int), Problem = @Problem;
        DROP TABLE #raw; RETURN;
    END CATCH;

    /* Personnel numbers this source uses that the roster has never heard of. */
    INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
    SELECT DISTINCT @SourceKey, @obj, ISNULL(r.SourceKeyText, N'(no key)'), N'PERSON_NOT_FOUND',
           N'"' + ISNULL(r.SourceKeyText, N'(no key)') + N'" is not a personnel number in the roster. '
         + N'Add a row to sel.PersonAlias if this source uses its own identifier.', @batch
    FROM #raw r WHERE r.PersonnelNo IS NULL;

    /* Item codes the catalogue has never seen.  Upsert them for review rather than
       dropping the evidence, and record each one. */
    INSERT sel.CatalogItem (ItemCode, Name, KindCode, NeedsReview)
    SELECT DISTINCT r.ItemCode, r.ItemCode, @KindCode, 1
    FROM #raw r
    WHERE r.ItemCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM sel.CatalogItem ci WHERE ci.KindCode = @KindCode AND ci.ItemCode = r.ItemCode);

    INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
    SELECT DISTINCT @SourceKey, @obj, r.RawItemCode, N'ITEM_CODE_UNKNOWN',
           N'"' + ISNULL(r.RawItemCode, N'(blank)') + N'" was not in the catalogue. '
         + N'It has been added for review — check it is not a differently written form of an existing code.', @batch
    FROM #raw r
    WHERE r.ItemCode IS NOT NULL
      AND EXISTS (SELECT 1 FROM sel.CatalogItem ci
                  WHERE ci.KindCode = @KindCode AND ci.ItemCode = r.ItemCode AND ci.NeedsReview = 1);

    INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
    SELECT @SourceKey, @obj, ISNULL(r.SourceKeyText, N'(no key)'), N'NO_ITEM_CODE',
           N'A row for ' + ISNULL(r.SourceKeyText, N'(no key)') + N' has no item code, so it cannot be matched.', @batch
    FROM #raw r WHERE r.ItemCode IS NULL OR r.ItemCode = N'';

    BEGIN TRAN;
    MERGE sel.EmployeeRecord AS t
    USING (SELECT PersonnelNo, ItemCode,
                  Status = MAX(Status), Score = MAX(Score), MaxScore = MAX(MaxScore),
                  CompletedOn = MAX(CompletedOn), ExpiresOn = MAX(ExpiresOn)
           FROM #raw
           WHERE PersonnelNo IS NOT NULL AND ItemCode IS NOT NULL AND ItemCode <> N''
           GROUP BY PersonnelNo, ItemCode) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.KindCode = @KindCode AND t.ItemCode = s.ItemCode
    WHEN MATCHED THEN UPDATE SET
        Status = s.Status, Score = s.Score, MaxScore = s.MaxScore,
        CompletedOn = s.CompletedOn, ExpiresOn = s.ExpiresOn,
        Source = @obj, LoadedOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, KindCode, ItemCode, Status, Score, MaxScore, CompletedOn, ExpiresOn, Source)
        VALUES (s.PersonnelNo, @KindCode, s.ItemCode, s.Status, s.Score, s.MaxScore,
                s.CompletedOn, s.ExpiresOn, @obj);
    DECLARE @loaded int = @@ROWCOUNT;
    COMMIT;

    UPDATE sel.TableMapping SET LastSyncUtc = SYSUTCDATETIME(),
           RowCountCached = (SELECT COUNT(*) FROM #raw) WHERE SourceKey = @SourceKey;
    UPDATE sel.EvidenceSource SET LastSyncUtc = SYSUTCDATETIME(),
           RowCountCached = (SELECT COUNT(*) FROM sel.EmployeeRecord WHERE KindCode = @KindCode)
    WHERE KindCode = @KindCode;

    SELECT SourceKey = @SourceKey, Loaded = @loaded,
           Exceptions = (SELECT COUNT(*) FROM stg.LoadException WHERE BatchId = @batch),
           Problem = CAST(NULL AS nvarchar(400));

    DROP TABLE #raw;
END
GO
PRINT '  sel.usp_Evidence_SyncOne          applied';
GO

/* sel.usp_Coverage_Sync — dbo.EmployeeCoverage into sel.EmployeeCoverage (the rows, for
   the conditions) AND sel.EmployeeMetric (the aggregate, for the criteria).  An
   aggregate cannot be taken apart again, which is why both are kept.                   */
CREATE OR ALTER PROCEDURE sel.usp_Coverage_Sync
    @LoginName nvarchar(128),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'EXPERIENCE');
    IF @obj IS NULL
    BEGIN
        SET @Problem = ISNULL((SELECT BreaksWhenUnmapped FROM sel.TableMapping WHERE SourceKey = N'EXPERIENCE'),
                              N'No coverage table is mapped.');
        SELECT SourceKey = N'EXPERIENCE', Loaded = CAST(NULL AS int), Problem = @Problem;
        RETURN;
    END;

    DECLARE @keyCol  nvarchar(128) = (SELECT KeyColumn  FROM sel.TableMapping WHERE SourceKey = N'EXPERIENCE');
    DECLARE @itemCol nvarchar(128) = (SELECT ItemColumn FROM sel.TableMapping WHERE SourceKey = N'EXPERIENCE');
    DECLARE @batch uniqueidentifier = NEWID();

    CREATE TABLE #cov
    (
        PersonnelNo nvarchar(30) NULL, SourceKeyText nvarchar(60) NULL,
        ItemCode nvarchar(60) NULL, CoverageType nvarchar(60) NULL,
        Department nvarchar(200) NULL, PositionSuffix nvarchar(30) NULL,
        StartDate date NULL, EndDate date NULL, Days decimal(18,4) NULL
    );

    DECLARE @deptExpr nvarchar(200) = N'CAST(NULL AS nvarchar(200))',
            @typeExpr nvarchar(200) = N'CAST(NULL AS nvarchar(60))',
            @startExpr nvarchar(200) = N'CAST(NULL AS date)',
            @endExpr  nvarchar(200) = N'CAST(NULL AS date)',
            @daysExpr nvarchar(200) = N'CAST(NULL AS decimal(18,4))';

    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = N'EXPERIENCE' AND c.ColumnName = N'Department')
        SET @deptExpr = N'TRY_CONVERT(nvarchar(200), src.[Department])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = N'EXPERIENCE' AND c.ColumnName = N'CoverageType')
        SET @typeExpr = N'TRY_CONVERT(nvarchar(60), src.[CoverageType])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = N'EXPERIENCE' AND c.ColumnName = N'StartDate')
        SET @startExpr = N'TRY_CONVERT(date, src.[StartDate])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = N'EXPERIENCE' AND c.ColumnName = N'EndDate')
        SET @endExpr = N'TRY_CONVERT(date, src.[EndDate])';
    IF EXISTS (SELECT 1 FROM sel.TableMappingColumn c JOIN sel.TableMapping m ON m.TableMappingId = c.TableMappingId
               WHERE m.SourceKey = N'EXPERIENCE' AND c.ColumnName = N'Days')
        SET @daysExpr = N'TRY_CONVERT(decimal(18,4), src.[Days])';

    DECLARE @sql nvarchar(max) = N'
        INSERT #cov (PersonnelNo, SourceKeyText, ItemCode, CoverageType, Department, PositionSuffix,
                     StartDate, EndDate, Days)
        SELECT COALESCE(e.PersonnelNo, al.PersonnelNo),
               TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@keyCol) + N'),
               UPPER(LTRIM(RTRIM(TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@itemCol) + N')))),
               ' + @typeExpr + N', ' + @deptExpr + N',
               TRY_CONVERT(nvarchar(30), src.' + QUOTENAME(@itemCol) + N'),
               ' + @startExpr + N', ' + @endExpr + N',
               /* If the source does not carry a day count, derive it from the dates. */
               COALESCE(' + @daysExpr + N',
                        CASE WHEN ' + @startExpr + N' IS NOT NULL AND ' + @endExpr + N' IS NOT NULL
                             THEN DATEDIFF(DAY, ' + @startExpr + N', ' + @endExpr + N') + 1 END)
        FROM ' + @obj + N' src
        LEFT JOIN sel.Employee e ON e.PersonnelNo = TRY_CONVERT(nvarchar(30), src.' + QUOTENAME(@keyCol) + N')
        LEFT JOIN sel.PersonAlias al ON al.AliasKey = TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@keyCol) + N')
                                    AND al.SourceKey IN (N''EXPERIENCE'', N''ALL'');';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @Problem = N'The coverage table could not be read: ' + ERROR_MESSAGE();
        SELECT SourceKey = N'EXPERIENCE', Loaded = CAST(NULL AS int), Problem = @Problem;
        DROP TABLE #cov; RETURN;
    END CATCH;

    INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText, BatchId)
    SELECT DISTINCT N'EXPERIENCE', @obj, ISNULL(c.SourceKeyText, N'(no key)'), N'PERSON_NOT_FOUND',
           N'"' + ISNULL(c.SourceKeyText, N'(no key)') + N'" is not a personnel number in the roster.', @batch
    FROM #cov c WHERE c.PersonnelNo IS NULL;

    BEGIN TRAN;
    /* The rows, replaced wholesale for the people this extract covers. */
    DELETE cv FROM sel.EmployeeCoverage cv
    WHERE cv.Source = @obj
      AND cv.PersonnelNo IN (SELECT DISTINCT PersonnelNo FROM #cov WHERE PersonnelNo IS NOT NULL);

    INSERT sel.EmployeeCoverage (PersonnelNo, ItemCode, CoverageType, Department, PositionSuffix,
                                 StartDate, EndDate, Days, Source)
    SELECT PersonnelNo, ItemCode, CoverageType, Department, PositionSuffix,
           StartDate, EndDate, Days, @obj
    FROM #cov WHERE PersonnelNo IS NOT NULL;
    DECLARE @loaded int = @@ROWCOUNT;
    COMMIT;

    UPDATE sel.TableMapping SET LastSyncUtc = SYSUTCDATETIME(), RowCountCached = @loaded
    WHERE SourceKey = N'EXPERIENCE';
    UPDATE sel.EvidenceSource SET LastSyncUtc = SYSUTCDATETIME() WHERE KindCode IN (N'COVERAGE', N'EXPERIENCE');

    SELECT SourceKey = N'EXPERIENCE', Loaded = @loaded,
           Exceptions = (SELECT COUNT(*) FROM stg.LoadException WHERE BatchId = @batch),
           Problem = CAST(NULL AS nvarchar(400));

    DROP TABLE #cov;
END
GO
PRINT '  sel.usp_Coverage_Sync             applied';
GO

/* sel.usp_Pmp_Sync — one row per person per year.  Never averaged on load: the average
   is a metric, computed afterwards, and can be undone.                                 */
CREATE OR ALTER PROCEDURE sel.usp_Pmp_Sync
    @LoginName nvarchar(128),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'PMP');
    IF @obj IS NULL
    BEGIN
        SET @Problem = ISNULL((SELECT BreaksWhenUnmapped FROM sel.TableMapping WHERE SourceKey = N'PMP'),
                              N'No performance table is mapped.');
        SELECT SourceKey = N'PMP', Loaded = CAST(NULL AS int), Problem = @Problem;
        RETURN;
    END;

    DECLARE @keyCol nvarchar(128) = (SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'PMP');
    DECLARE @sql nvarchar(max) = N'
        MERGE sel.EmployeePmp AS t
        USING (SELECT PersonnelNo = COALESCE(e.PersonnelNo, al.PersonnelNo),
                      RatingYear  = TRY_CONVERT(smallint, src.[RatingYear]),
                      RatingCode  = TRY_CONVERT(nvarchar(20), src.[RatingCode]),
                      RatingValue = TRY_CONVERT(decimal(18,4), src.[RatingValue])
               FROM ' + @obj + N' src
               LEFT JOIN sel.Employee e ON e.PersonnelNo = TRY_CONVERT(nvarchar(30), src.' + QUOTENAME(@keyCol) + N')
               LEFT JOIN sel.PersonAlias al ON al.AliasKey = TRY_CONVERT(nvarchar(60), src.' + QUOTENAME(@keyCol) + N')
                                           AND al.SourceKey IN (N''PMP'', N''ALL'')) AS s
           ON t.PersonnelNo = s.PersonnelNo AND t.RatingYear = s.RatingYear
        WHEN MATCHED THEN UPDATE SET RatingCode = s.RatingCode, RatingValue = s.RatingValue,
                                     Source = @obj, LoadedOnUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET AND s.PersonnelNo IS NOT NULL AND s.RatingYear IS NOT NULL THEN
            INSERT (PersonnelNo, RatingYear, RatingCode, RatingValue, Source)
            VALUES (s.PersonnelNo, s.RatingYear, s.RatingCode, s.RatingValue, @obj);';

    DECLARE @loaded int = 0;
    BEGIN TRY
        EXEC sp_executesql @sql, N'@obj nvarchar(300)', @obj = @obj;
        SET @loaded = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        SET @Problem = N'The performance table could not be read: ' + ERROR_MESSAGE();
        SELECT SourceKey = N'PMP', Loaded = CAST(NULL AS int), Problem = @Problem;
        RETURN;
    END CATCH;

    UPDATE sel.TableMapping SET LastSyncUtc = SYSUTCDATETIME(), RowCountCached = @loaded WHERE SourceKey = N'PMP';
    SELECT SourceKey = N'PMP', Loaded = @loaded, Exceptions = 0, Problem = CAST(NULL AS nvarchar(400));
END
GO
PRINT '  sel.usp_Pmp_Sync                  applied';
GO

/* sel.usp_Evidence_SyncAll — every source in order, finishing with the metric rebuild. */
CREATE OR ALTER PROCEDURE sel.usp_Evidence_SyncAll
    @LoginName nvarchar(128),
    @AsOf      date = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    IF sec.fn_ScreenAccess(@LoginName, N'/Admin/Policy/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(40)) AS SourceKey; RETURN;
    END;

    CREATE TABLE #result (SourceKey nvarchar(40), Loaded int NULL, Exceptions int NULL, Problem nvarchar(400) NULL);

    DECLARE @p nvarchar(400);
    INSERT #result EXEC sel.usp_Evidence_SyncOne @LoginName = @LoginName, @SourceKey = N'COURSE',
           @KindCode = N'COURSE', @Problem = @p OUTPUT;
    INSERT #result EXEC sel.usp_Evidence_SyncOne @LoginName = @LoginName, @SourceKey = N'ASSESSMENT',
           @KindCode = N'ASSESSMENT', @Problem = @p OUTPUT;
    INSERT #result EXEC sel.usp_Evidence_SyncOne @LoginName = @LoginName, @SourceKey = N'FEEDBACK360',
           @KindCode = N'FEEDBACK360', @Problem = @p OUTPUT;
    INSERT #result EXEC sel.usp_Coverage_Sync @LoginName = @LoginName, @Problem = @p OUTPUT;
    INSERT #result EXEC sel.usp_Pmp_Sync @LoginName = @LoginName, @Problem = @p OUTPUT;

    /* The aggregates the criteria builder filters on, rebuilt last. */
    EXEC sel.usp_Metric_Refresh @LoginName = @LoginName, @AsOf = @AsOf;

    EXEC audit.usp_Log @TableName = N'sel.EmployeeRecord', @KeyText = N'(sync all)', @ActionCode = N'SYNC',
                       @LoginName = @LoginName;

    /* A source that could not be read is reported, not hidden. */
    SELECT SourceKey, Loaded, Exceptions, Problem FROM #result ORDER BY SourceKey;

    DECLARE @failed int = (SELECT COUNT(*) FROM #result WHERE Problem IS NOT NULL);
    IF @failed > 0
        SET @Problem = CONVERT(nvarchar(10), @failed) + N' source'
                     + CASE WHEN @failed = 1 THEN N' could' ELSE N's could' END
                     + N' not be read. Every requirement that names them can never be met.';

    DROP TABLE #result;
END
GO
PRINT '  sel.usp_Evidence_SyncAll          applied';
GO

/* sel.usp_LoadException_Resolve — marking one dealt with, so the screen shows what is
   still outstanding rather than the whole history.                                     */
CREATE OR ALTER PROCEDURE sel.usp_LoadException_Resolve
    @LoginName       nvarchar(128),
    @LoadExceptionId bigint,
    @Problem         nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Admin/Policy/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS LoadExceptionId; RETURN;
    END;

    UPDATE stg.LoadException
       SET IsResolved = 1, ResolvedOnUtc = SYSUTCDATETIME(), ResolvedByLogin = @LoginName
    WHERE LoadExceptionId = @LoadExceptionId;

    SELECT LoadExceptionId = @LoadExceptionId, Resolved = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_LoadException_Resolve     applied';
GO

/* sel.usp_PersonAlias_Save — the answer to a personnel-number mismatch. */
CREATE OR ALTER PROCEDURE sel.usp_PersonAlias_Save
    @LoginName   nvarchar(128),
    @SourceKey   nvarchar(40),
    @AliasKey    nvarchar(60),
    @PersonnelNo nvarchar(30),
    @Note        nvarchar(400) = NULL,
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Admin/Policy/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS PersonAliasId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.Employee WHERE PersonnelNo = @PersonnelNo)
    BEGIN
        SET @Problem = N'"' + @PersonnelNo + N'" is not a personnel number in the roster, so nothing can be mapped to it.';
        SELECT TOP (0) CAST(NULL AS int) AS PersonAliasId; RETURN;
    END;

    MERGE sel.PersonAlias AS t
    USING (SELECT @SourceKey AS SourceKey, @AliasKey AS AliasKey) AS s
       ON t.SourceKey = s.SourceKey AND t.AliasKey = s.AliasKey
    WHEN MATCHED THEN UPDATE SET PersonnelNo = @PersonnelNo, Note = @Note
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (SourceKey, AliasKey, PersonnelNo, Note)
        VALUES (s.SourceKey, s.AliasKey, @PersonnelNo, @Note);

    DECLARE @keyText nvarchar(200) = @SourceKey + N'/' + @AliasKey;
    EXEC audit.usp_Log @TableName = N'sel.PersonAlias', @KeyText = @keyText, @ActionCode = N'SAVE',
                       @LoginName = @LoginName;

    SELECT SourceKey = @SourceKey, AliasKey = @AliasKey, PersonnelNo = @PersonnelNo;
END
GO
PRINT '  sel.usp_PersonAlias_Save          applied';
GO

/* sel.usp_Employee_Roster — the Employee roster screen: a server-paged read of the
   mapped roster, with search, sort and page size.  Sensitive columns are readable on a
   record but refused as filters, and the refusal says why.                             */
CREATE OR ALTER PROCEDURE sel.usp_Employee_Roster
    @LoginName nvarchar(128),
    @Search    nvarchar(200) = NULL,
    @OrgCode   nvarchar(40) = NULL,
    @SortBy    nvarchar(128) = NULL,
    @SortDir   nvarchar(4) = N'ASC',
    @PageNo    int = 1,
    @PageSize  int = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageSize > CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_MAX'), 500) AS int)
        SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_MAX'), 500) AS int);
    IF @PageNo IS NULL OR @PageNo < 1 SET @PageNo = 1;
    /* A NULL direction is the default, not a value to compare: NULL NOT IN (...) is
       unknown, so the test below would leave it NULL, the ORDER BY clause would
       concatenate to NULL, and the whole statement would become NULL — which returns no
       rows at all rather than an error. ISNULL first. */
    SET @SortDir = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@SortDir)), N''), N'ASC'));
    IF @SortDir NOT IN (N'ASC', N'DESC') SET @SortDir = N'ASC';

    DECLARE @order nvarchar(200) = N'e.FullName ' + @SortDir;
    IF @SortBy IN (N'PersonnelNo', N'FullName', N'JobTitle', N'GradeCode', N'PermJobSuffix', N'HireDate')
        SET @order = N'e.' + QUOTENAME(@SortBy) + N' ' + @SortDir;
    ELSE IF @SortBy IS NOT NULL AND EXISTS (SELECT 1 FROM sel.ColumnCatalog WHERE ColumnName = @SortBy AND IsSensitive = 1)
    BEGIN
        SET @Problem = cfg.fn_Message(N'SENSITIVE_FILTER');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        SELECT TotalRows = CAST(NULL AS int); RETURN;
    END;

    DECLARE @sql nvarchar(max) = N'
        SELECT e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
               e.PermJobSuffix, e.PermJobSuffixDesc, e.GradeCode, e.ManagementLevelCode,
               e.HireDate, e.PromotionDate, e.IsActive, e.PermChiefInd
        FROM sel.Employee e
        JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
        LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
        WHERE (@OrgCode IS NULL OR e.OrgCode = @OrgCode)
          AND (@Search IS NULL OR e.FullName LIKE N''%'' + @Search + N''%''
               OR e.PersonnelNo LIKE N''%'' + @Search + N''%''
               OR e.JobTitle LIKE N''%'' + @Search + N''%''
               OR o.Name LIKE N''%'' + @Search + N''%'')
        ORDER BY ' + @order + N'
        OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;';

    EXEC sp_executesql @sql,
         N'@LoginName nvarchar(128), @OrgCode nvarchar(40), @Search nvarchar(200), @PageNo int, @PageSize int',
         @LoginName = @LoginName, @OrgCode = @OrgCode, @Search = @Search, @PageNo = @PageNo, @PageSize = @PageSize;

    SELECT TotalRows = COUNT(*)
    FROM sel.Employee e
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    WHERE (@OrgCode IS NULL OR e.OrgCode = @OrgCode)
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
           OR e.PersonnelNo LIKE N'%' + @Search + N'%'
           OR e.JobTitle LIKE N'%' + @Search + N'%'
           OR o.Name LIKE N'%' + @Search + N'%');
END
GO
PRINT '  sel.usp_Employee_Roster           applied';
GO

PRINT '== 13_loads complete =================================================';
GO
