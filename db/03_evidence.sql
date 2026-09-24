/* =====================================================================================
   03_evidence.sql  —  what a person has actually done
   -------------------------------------------------------------------------------------
   A requirement kind says how evidence for it is judged (a flag, or a sum).  An evidence
   source says where that evidence lives.  sel.EmployeeRecord holds flag-mode evidence and
   sel.EmployeeCoverage holds sum-mode rows; sel.EmployeeRecordDetail lets a condition name
   a column the extract carried that this schema never anticipated.

   dbo.EmployeeCoverage is a *source* table; sel.EmployeeCoverage is the application's copy
   loaded from it.  The two are distinct and are never joined across.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 03_evidence =======================================================';
GO

/* --- sel.RequirementKind --------------------------------------------------------
   EvalModeCode is how the engine judges this kind.  Never an if (kind = 'COVERAGE'). */
IF OBJECT_ID('sel.RequirementKind') IS NULL
BEGIN
    CREATE TABLE sel.RequirementKind
    (
        KindCode        nvarchar(30)  NOT NULL CONSTRAINT PK_sel_RequirementKind PRIMARY KEY,
        Name            nvarchar(120) NOT NULL,
        Description     nvarchar(400) NULL,
        EvalModeCode    nvarchar(20)  NOT NULL,        -- FLAG | SUM
        MeasureDomain   nvarchar(60)  NULL,            -- which cfg.Domain its measure comes from
        DefaultRuleText nvarchar(600) NULL,            -- what an event with no condition sets follows
        SortOrder       int           NOT NULL CONSTRAINT DF_sel_RequirementKind_Sort DEFAULT (0),
        IsActive        bit           NOT NULL CONSTRAINT DF_sel_RequirementKind_Act  DEFAULT (1)
    );
    PRINT '  sel.RequirementKind               created';
END
ELSE PRINT '  sel.RequirementKind               skipped';
GO

/* --- sel.CatalogItem ------------------------------------------------------------
   The catalogue of codes.  A load that meets a code it has never seen upserts it here
   with NeedsReview = 1 rather than dropping the row on the floor.                    */
IF OBJECT_ID('sel.CatalogItem') IS NULL
BEGIN
    CREATE TABLE sel.CatalogItem
    (
        CatalogItemId  int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CatalogItem PRIMARY KEY,
        ItemCode       nvarchar(60)  NOT NULL,
        Name           nvarchar(300) NOT NULL,
        KindCode       nvarchar(30)  NOT NULL CONSTRAINT FK_sel_CatalogItem_Kind REFERENCES sel.RequirementKind(KindCode),
        CategoryValueId int          NULL CONSTRAINT FK_sel_CatalogItem_Cat REFERENCES cfg.DomainValue(DomainValueId),
        NeedsReview    bit           NOT NULL CONSTRAINT DF_sel_CatalogItem_Review DEFAULT (0),
        IsActive       bit           NOT NULL CONSTRAINT DF_sel_CatalogItem_Active DEFAULT (1),
        FirstSeenUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_CatalogItem_Seen   DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_CatalogItem UNIQUE (KindCode, ItemCode)
    );
    CREATE INDEX IX_sel_CatalogItem_Code ON sel.CatalogItem (ItemCode);
    PRINT '  sel.CatalogItem                   created';
END
ELSE PRINT '  sel.CatalogItem                   skipped';
GO

/* --- sel.EvidenceSource ---------------------------------------------------------
   Where each kind's evidence lives, and the join stated in its own row rather than
   written into a query.  A kind with items pointing at it and no table mapped must
   warn that those requirements can never be met.                                     */
IF OBJECT_ID('sel.EvidenceSource') IS NULL
BEGIN
    CREATE TABLE sel.EvidenceSource
    (
        EvidenceSourceId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_EvidenceSource PRIMARY KEY,
        KindCode        nvarchar(30)  NOT NULL CONSTRAINT FK_sel_EvidenceSource_Kind REFERENCES sel.RequirementKind(KindCode),
        SourceKey       nvarchar(40)  NULL CONSTRAINT FK_sel_EvidenceSource_Map
                                          REFERENCES sel.TableMapping(SourceKey),
        /* The application table the engine reads for this kind. */
        AppSchema       nvarchar(128) NOT NULL CONSTRAINT DF_sel_EvidenceSource_Schema DEFAULT (N'sel'),
        AppTable        nvarchar(128) NOT NULL,
        KeyColumn       nvarchar(128) NOT NULL CONSTRAINT DF_sel_EvidenceSource_Key    DEFAULT (N'PersonnelNo'),
        ItemColumn      nvarchar(128) NULL,
        /* The column a flag-mode default rule tests, and the value that passes it. */
        StatusColumn    nvarchar(128) NULL,
        PassValue       nvarchar(120) NULL,
        /* The column a sum-mode kind sums. */
        MeasureColumn   nvarchar(128) NULL,
        IsMapped        bit           NOT NULL CONSTRAINT DF_sel_EvidenceSource_Mapped DEFAULT (0),
        RowCountCached  bigint        NULL,
        LastSyncUtc     datetime2(3)  NULL,
        CONSTRAINT UQ_sel_EvidenceSource UNIQUE (KindCode)
    );
    PRINT '  sel.EvidenceSource                created';
END
ELSE PRINT '  sel.EvidenceSource                skipped';
GO

/* --- sel.EvidenceSourceColumn ---------------------------------------------------
   The fields a completion condition may name.  A field typed once in the rule editor
   is learned into this list and offered to every event after, so the second author
   picks from a list instead of guessing at a spelling.                               */
IF OBJECT_ID('sel.EvidenceSourceColumn') IS NULL
BEGIN
    CREATE TABLE sel.EvidenceSourceColumn
    (
        EvidenceSourceColumnId int    IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_EvidenceSourceColumn PRIMARY KEY,
        EvidenceSourceId int          NOT NULL CONSTRAINT FK_sel_ESC_Source REFERENCES sel.EvidenceSource(EvidenceSourceId),
        ColumnName      nvarchar(128) NOT NULL,
        Caption         nvarchar(160) NULL,
        DataType        nvarchar(20)  NOT NULL CONSTRAINT DF_sel_ESC_Type DEFAULT (N'text'),
        /* An expiry date proposes "is after today" rather than "equals". */
        IsExpiryDate    bit           NOT NULL CONSTRAINT DF_sel_ESC_Expiry   DEFAULT (0),
        /* A real column of the application table, or a key in EmployeeRecordDetail. */
        IsPhysical      bit           NOT NULL CONSTRAINT DF_sel_ESC_Physical DEFAULT (1),
        IsLearned       bit           NOT NULL CONSTRAINT DF_sel_ESC_Learned  DEFAULT (0),
        UsageCount      int           NOT NULL CONSTRAINT DF_sel_ESC_Usage    DEFAULT (0),
        SortOrder       int           NOT NULL CONSTRAINT DF_sel_ESC_Sort     DEFAULT (0),
        CONSTRAINT UQ_sel_ESC UNIQUE (EvidenceSourceId, ColumnName)
    );
    PRINT '  sel.EvidenceSourceColumn          created';
END
ELSE PRINT '  sel.EvidenceSourceColumn          skipped';
GO

/* --- sel.EmployeeRecord ---------------------------------------------------------
   Flag-mode evidence: a course completion, an assessment result, a 360 survey.
   Indexed so a lookup is a seek on (KindCode, ItemCode) or (PersonnelNo, KindCode),
   never a scan — the engine reads this table once per item across the whole pool.    */
IF OBJECT_ID('sel.EmployeeRecord') IS NULL
BEGIN
    CREATE TABLE sel.EmployeeRecord
    (
        EmployeeRecordId bigint       IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_EmployeeRecord PRIMARY KEY,
        PersonnelNo     nvarchar(30)  NOT NULL,
        KindCode        nvarchar(30)  NOT NULL,
        ItemCode        nvarchar(60)  NOT NULL,
        Status          nvarchar(60)  NULL,
        Score           decimal(18,4) NULL,
        MaxScore        decimal(18,4) NULL,
        CompletedOn     date          NULL,
        StartedOn       date          NULL,
        ExpiresOn       date          NULL,
        AttemptNo       int           NULL,
        Source          nvarchar(260) NULL,
        LoadedOnUtc     datetime2(3)  NOT NULL CONSTRAINT DF_sel_EmployeeRecord_Loaded DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_EmployeeRecord UNIQUE (PersonnelNo, KindCode, ItemCode)
    );
    CREATE INDEX IX_sel_EmployeeRecord_Item   ON sel.EmployeeRecord (KindCode, ItemCode)
        INCLUDE (PersonnelNo, Status, Score, MaxScore, CompletedOn, ExpiresOn);
    CREATE INDEX IX_sel_EmployeeRecord_Person ON sel.EmployeeRecord (PersonnelNo, KindCode)
        INCLUDE (ItemCode, Status, Score, CompletedOn, ExpiresOn);
    PRINT '  sel.EmployeeRecord                created';
END
ELSE PRINT '  sel.EmployeeRecord                skipped';
GO

/* --- sel.EmployeeRecordDetail ---------------------------------------------------
   The columns an extract carried that this schema never anticipated.  A condition may
   name one of these, and the engine reads it through here rather than needing a
   migration for every new source column.                                             */
IF OBJECT_ID('sel.EmployeeRecordDetail') IS NULL
BEGIN
    CREATE TABLE sel.EmployeeRecordDetail
    (
        EmployeeRecordDetailId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_EmployeeRecordDetail PRIMARY KEY,
        EmployeeRecordId bigint       NOT NULL CONSTRAINT FK_sel_ERD_Record REFERENCES sel.EmployeeRecord(EmployeeRecordId),
        FieldName       nvarchar(128) NOT NULL,
        ValueText       nvarchar(400) NULL,
        ValueNum        decimal(18,4) NULL,
        ValueDate       date          NULL,
        CONSTRAINT UQ_sel_ERD UNIQUE (EmployeeRecordId, FieldName)
    );
    CREATE INDEX IX_sel_ERD_Field ON sel.EmployeeRecordDetail (FieldName) INCLUDE (EmployeeRecordId, ValueText, ValueNum, ValueDate);
    PRINT '  sel.EmployeeRecordDetail          created';
END
ELSE PRINT '  sel.EmployeeRecordDetail          skipped';
GO

/* --- sel.EmployeeCoverage -------------------------------------------------------
   Sum-mode evidence: acting and coverage spells.  Rows for the conditions; the
   aggregate lives in sel.EmployeeMetric for the criteria, because an aggregate cannot
   be taken apart again.                                                              */
IF OBJECT_ID('sel.EmployeeCoverage') IS NULL
BEGIN
    CREATE TABLE sel.EmployeeCoverage
    (
        EmployeeCoverageId bigint     IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_EmployeeCoverage PRIMARY KEY,
        PersonnelNo     nvarchar(30)  NOT NULL,
        ItemCode        nvarchar(60)  NULL,          -- the position suffix or curriculum this covers
        CoverageType    nvarchar(60)  NULL,
        Department      nvarchar(200) NULL,
        OrgCode         nvarchar(40)  NULL,
        PositionSuffix  nvarchar(30)  NULL,
        PositionCode    nvarchar(60)  NULL,
        StartDate       date          NULL,
        EndDate         date          NULL,
        Days            decimal(18,4) NULL,
        Months          decimal(18,4) NULL,
        Source          nvarchar(260) NULL,
        LoadedOnUtc     datetime2(3)  NOT NULL CONSTRAINT DF_sel_EmployeeCoverage_Loaded DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_sel_EmpCoverage_Person ON sel.EmployeeCoverage (PersonnelNo)
        INCLUDE (ItemCode, CoverageType, PositionSuffix, Department, StartDate, EndDate, Days, Months);
    CREATE INDEX IX_sel_EmpCoverage_Item   ON sel.EmployeeCoverage (ItemCode) INCLUDE (PersonnelNo, Days, Months);
    PRINT '  sel.EmployeeCoverage              created';
END
ELSE PRINT '  sel.EmployeeCoverage              skipped';
GO

/* --- sel.EmployeePmp ------------------------------------------------------------
   One row per person per year.  Never averaged on load — the profile shows the last
   three years as letters, and an average computed at load time cannot be undone.     */
IF OBJECT_ID('sel.EmployeePmp') IS NULL
BEGIN
    CREATE TABLE sel.EmployeePmp
    (
        PersonnelNo   nvarchar(30)  NOT NULL,
        RatingYear    smallint      NOT NULL,
        RatingCode    nvarchar(20)  NULL,
        RatingValue   decimal(18,4) NULL,
        Source        nvarchar(260) NULL,
        LoadedOnUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_EmployeePmp_Loaded DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sel_EmployeePmp PRIMARY KEY (PersonnelNo, RatingYear)
    );
    PRINT '  sel.EmployeePmp                   created';
END
ELSE PRINT '  sel.EmployeePmp                   skipped';
GO

/* --- sel.MetricDefinition / sel.EmployeeMetric ----------------------------------
   Derived per-person figures the criteria builder may filter on (DaysCovered, the
   three-year performance average, mandatory course count).                           */
IF OBJECT_ID('sel.MetricDefinition') IS NULL
BEGIN
    CREATE TABLE sel.MetricDefinition
    (
        MetricKey   nvarchar(60)  NOT NULL CONSTRAINT PK_sel_MetricDefinition PRIMARY KEY,
        Name        nvarchar(160) NOT NULL,
        Description nvarchar(400) NULL,
        DataType    nvarchar(20)  NOT NULL CONSTRAINT DF_sel_MetricDefinition_Type DEFAULT (N'number'),
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_MetricDefinition_Sort DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sel_MetricDefinition_Act  DEFAULT (1)
    );
    PRINT '  sel.MetricDefinition              created';
END
ELSE PRINT '  sel.MetricDefinition              skipped';
GO

IF OBJECT_ID('sel.EmployeeMetric') IS NULL
BEGIN
    CREATE TABLE sel.EmployeeMetric
    (
        PersonnelNo nvarchar(30)  NOT NULL,
        MetricKey   nvarchar(60)  NOT NULL CONSTRAINT FK_sel_EmployeeMetric_Def REFERENCES sel.MetricDefinition(MetricKey),
        NumValue    decimal(18,4) NULL,
        TextValue   nvarchar(400) NULL,
        AsOfDate    date          NULL,
        RefreshedUtc datetime2(3) NOT NULL CONSTRAINT DF_sel_EmployeeMetric_Ref DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sel_EmployeeMetric PRIMARY KEY (PersonnelNo, MetricKey)
    );
    CREATE INDEX IX_sel_EmployeeMetric_Key ON sel.EmployeeMetric (MetricKey) INCLUDE (PersonnelNo, NumValue, TextValue);
    PRINT '  sel.EmployeeMetric                created';
END
ELSE PRINT '  sel.EmployeeMetric                skipped';
GO

/* =====================================================================================
   Procedures
   ===================================================================================== */

/* sel.usp_EvidenceSource_List — the Data sources panel.  Each row states its own join
   in a sentence built from the live values, so the sentence cannot drift from the rule
   it describes.                                                                        */
CREATE OR ALTER PROCEDURE sel.usp_EvidenceSource_List
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.EvidenceSourceId, s.KindCode, k.Name AS KindName, k.EvalModeCode,
           s.SourceKey, s.AppSchema, s.AppTable, s.KeyColumn, s.ItemColumn,
           s.StatusColumn, s.PassValue, s.MeasureColumn,
           s.IsMapped, s.RowCountCached, s.LastSyncUtc,
           SourceTable = m.SchemaName + N'.' + m.TableName,
           SourceIsMapped = ISNULL(m.IsMapped, 0),
           /* What depends on this source. */
           ItemCount  = (SELECT COUNT(*) FROM sel.CatalogItem ci WHERE ci.KindCode = s.KindCode AND ci.IsActive = 1),
           EventCount = (SELECT COUNT(*) FROM sel.DevEvent de WHERE de.KindCode = s.KindCode AND de.IsActive = 1),
           /* The join, stated not configured. */
           JoinSentence =
               CASE WHEN k.EvalModeCode = N'SUM'
                    THEN N'Read from ' + s.AppSchema + N'.' + s.AppTable + N' for this person. '
                       + N'The conditions below decide which rows count, and '
                       + ISNULL(s.MeasureColumn, N'the measure') + N' is summed over the survivors.'
                    ELSE N'A requirement naming an item is matched where ' + s.AppSchema + N'.' + s.AppTable
                       + N'.' + ISNULL(s.ItemColumn, N'ItemCode') + N' equals that item''s code'
                       + CASE WHEN s.StatusColumn IS NOT NULL AND s.PassValue IS NOT NULL
                              THEN N', and is met when ' + s.StatusColumn + N' equals ' + s.PassValue + N'.'
                              ELSE N'.' END
               END,
           /* A kind with items and no table mapped can never be met, and must say so. */
           Warning = CASE WHEN s.IsMapped = 0
                           AND EXISTS (SELECT 1 FROM sel.CatalogItem ci WHERE ci.KindCode = s.KindCode AND ci.IsActive = 1)
                          THEN cfg.fn_Message(N'SOURCE_UNMAPPED') ELSE NULL END
    FROM sel.EvidenceSource s
    JOIN sel.RequirementKind k ON k.KindCode = s.KindCode
    LEFT JOIN sel.TableMapping m ON m.SourceKey = s.SourceKey
    ORDER BY k.SortOrder, k.Name;

    SELECT c.EvidenceSourceColumnId, c.EvidenceSourceId, s.KindCode, c.ColumnName, c.Caption,
           c.DataType, c.IsExpiryDate, c.IsPhysical, c.IsLearned, c.UsageCount, c.SortOrder
    FROM sel.EvidenceSourceColumn c
    JOIN sel.EvidenceSource s ON s.EvidenceSourceId = c.EvidenceSourceId
    ORDER BY s.KindCode, c.SortOrder, c.ColumnName;
END
GO
PRINT '  sel.usp_EvidenceSource_List       applied';
GO

/* sel.usp_EvidenceSourceColumn_Learn — a field typed once in the rule editor becomes a
   suggestion for every event after.  Learned fields are not physical columns, so the
   engine reads them through sel.EmployeeRecordDetail.                                 */
CREATE OR ALTER PROCEDURE sel.usp_EvidenceSourceColumn_Learn
    @LoginName  nvarchar(128),
    @KindCode   nvarchar(30),
    @ColumnName nvarchar(128),
    @DataType   nvarchar(20) = NULL,
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS EvidenceSourceColumnId;
        RETURN;
    END;

    DECLARE @sourceId int, @schema nvarchar(128), @table nvarchar(128);
    SELECT @sourceId = EvidenceSourceId, @schema = AppSchema, @table = AppTable
    FROM sel.EvidenceSource WHERE KindCode = @KindCode;

    IF @sourceId IS NULL
    BEGIN
        SET @Problem = N'There is no evidence source for the kind ' + @KindCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS EvidenceSourceColumnId;
        RETURN;
    END;

    SET @ColumnName = LTRIM(RTRIM(@ColumnName));
    IF NULLIF(@ColumnName, N'') IS NULL
    BEGIN
        SET @Problem = N'A condition needs a field name before it can be saved.';
        SELECT TOP (0) CAST(NULL AS int) AS EvidenceSourceColumnId;
        RETURN;
    END;

    /* Is it a real column of the application table, or a learned detail key? */
    DECLARE @isPhysical bit = 0, @sqlType nvarchar(60);
    SELECT @sqlType = DATA_TYPE FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table AND COLUMN_NAME = @ColumnName;
    IF @sqlType IS NOT NULL SET @isPhysical = 1;

    IF @DataType IS NULL
        SET @DataType = CASE WHEN @sqlType IS NOT NULL THEN sel.fn_SqlTypeToDataType(@sqlType) ELSE N'text' END;

    IF NOT EXISTS (SELECT 1 FROM sel.EvidenceSourceColumn
                   WHERE EvidenceSourceId = @sourceId AND ColumnName = @ColumnName)
    BEGIN
        INSERT sel.EvidenceSourceColumn (EvidenceSourceId, ColumnName, Caption, DataType, IsExpiryDate, IsPhysical, IsLearned, SortOrder)
        VALUES (@sourceId, @ColumnName, @ColumnName, @DataType,
                /* A name that reads like an expiry proposes "is after today". */
                CASE WHEN @ColumnName IN (N'ExpiresOn', N'EndDate', N'ValidTo', N'DueDate', N'ExpiryDate')
                     THEN 1 ELSE 0 END,
                @isPhysical, 1,
                ISNULL((SELECT MAX(SortOrder) + 1 FROM sel.EvidenceSourceColumn WHERE EvidenceSourceId = @sourceId), 100));

        EXEC audit.usp_Log @TableName = N'sel.EvidenceSourceColumn', @KeyText = @ColumnName,
                           @ActionCode = N'LEARN', @LoginName = @LoginName;
    END;

    UPDATE sel.EvidenceSourceColumn
       SET UsageCount = UsageCount + 1
    WHERE EvidenceSourceId = @sourceId AND ColumnName = @ColumnName;

    SELECT EvidenceSourceColumnId, EvidenceSourceId, ColumnName, Caption, DataType,
           IsExpiryDate, IsPhysical, IsLearned, UsageCount
    FROM sel.EvidenceSourceColumn
    WHERE EvidenceSourceId = @sourceId AND ColumnName = @ColumnName;
END
GO
PRINT '  sel.usp_EvidenceSourceColumn_Learn applied';
GO

/* sel.usp_CatalogItem_List — the catalogue, with the codes a load could not place. */
CREATE OR ALTER PROCEDURE sel.usp_CatalogItem_List
    @LoginName   nvarchar(128),
    @KindCode    nvarchar(30) = NULL,
    @Search      nvarchar(200) = NULL,
    @NeedsReviewOnly bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ci.CatalogItemId, ci.ItemCode, ci.Name, ci.KindCode, k.Name AS KindName,
           ci.CategoryValueId, dv.ValueCode AS CategoryCode, dv.Name AS CategoryName,
           ci.NeedsReview, ci.IsActive, ci.FirstSeenUtc,
           RecordCount = (SELECT COUNT(*) FROM sel.EmployeeRecord r
                          WHERE r.KindCode = ci.KindCode AND r.ItemCode = ci.ItemCode)
    FROM sel.CatalogItem ci
    JOIN sel.RequirementKind k ON k.KindCode = ci.KindCode
    LEFT JOIN cfg.DomainValue dv ON dv.DomainValueId = ci.CategoryValueId
    WHERE (@KindCode IS NULL OR ci.KindCode = @KindCode)
      AND (@Search IS NULL OR ci.ItemCode LIKE N'%' + @Search + N'%' OR ci.Name LIKE N'%' + @Search + N'%')
      AND (@NeedsReviewOnly = 0 OR ci.NeedsReview = 1)
    ORDER BY ci.KindCode, ci.ItemCode;
END
GO
PRINT '  sel.usp_CatalogItem_List          applied';
GO

/* sel.usp_Metric_Refresh — rebuilds the derived per-person figures after a load.
   Set-based, one statement per metric.                                                */
CREATE OR ALTER PROCEDURE sel.usp_Metric_Refresh
    @LoginName nvarchar(128) = NULL,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    BEGIN TRAN;

    /* DaysCovered — the aggregate the criteria builder filters on. */
    MERGE sel.EmployeeMetric AS t
    USING (SELECT PersonnelNo, NumValue = SUM(ISNULL(Days, 0))
           FROM sel.EmployeeCoverage GROUP BY PersonnelNo) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.MetricKey = N'DaysCovered'
    WHEN MATCHED THEN UPDATE SET NumValue = s.NumValue, AsOfDate = @AsOf, RefreshedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, MetricKey, NumValue, AsOfDate) VALUES (s.PersonnelNo, N'DaysCovered', s.NumValue, @AsOf);

    /* PerformanceAvg3 — the three-year average, computed here and not at load time. */
    MERGE sel.EmployeeMetric AS t
    USING (SELECT PersonnelNo, NumValue = AVG(RatingValue)
           FROM (SELECT PersonnelNo, RatingValue,
                        rn = ROW_NUMBER() OVER (PARTITION BY PersonnelNo ORDER BY RatingYear DESC)
                 FROM sel.EmployeePmp WHERE RatingValue IS NOT NULL) z
           WHERE rn <= 3 GROUP BY PersonnelNo) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.MetricKey = N'PerformanceAvg3'
    WHEN MATCHED THEN UPDATE SET NumValue = s.NumValue, AsOfDate = @AsOf, RefreshedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, MetricKey, NumValue, AsOfDate) VALUES (s.PersonnelNo, N'PerformanceAvg3', s.NumValue, @AsOf);

    /* CoursesCompleted */
    MERGE sel.EmployeeMetric AS t
    USING (SELECT PersonnelNo, NumValue = CAST(COUNT(*) AS decimal(18,4))
           FROM sel.EmployeeRecord WHERE KindCode = N'COURSE' AND Status = N'Completed'
           GROUP BY PersonnelNo) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.MetricKey = N'CoursesCompleted'
    WHEN MATCHED THEN UPDATE SET NumValue = s.NumValue, AsOfDate = @AsOf, RefreshedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, MetricKey, NumValue, AsOfDate) VALUES (s.PersonnelNo, N'CoursesCompleted', s.NumValue, @AsOf);

    /* DirectorActingDays — coverage against a director-level position suffix. */
    MERGE sel.EmployeeMetric AS t
    USING (SELECT PersonnelNo, NumValue = SUM(ISNULL(Days, 0))
           FROM sel.EmployeeCoverage
           WHERE CoverageType = N'Acting' AND PositionSuffix IS NOT NULL
           GROUP BY PersonnelNo) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.MetricKey = N'DirectorActingDays'
    WHEN MATCHED THEN UPDATE SET NumValue = s.NumValue, AsOfDate = @AsOf, RefreshedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, MetricKey, NumValue, AsOfDate) VALUES (s.PersonnelNo, N'DirectorActingDays', s.NumValue, @AsOf);

    /* TenureYears — against the as-of date, never against today. */
    MERGE sel.EmployeeMetric AS t
    USING (SELECT PersonnelNo, NumValue = CAST(DATEDIFF(DAY, HireDate, @AsOf) / 365.25 AS decimal(18,4))
           FROM sel.Employee WHERE HireDate IS NOT NULL) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.MetricKey = N'TenureYears'
    WHEN MATCHED THEN UPDATE SET NumValue = s.NumValue, AsOfDate = @AsOf, RefreshedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, MetricKey, NumValue, AsOfDate) VALUES (s.PersonnelNo, N'TenureYears', s.NumValue, @AsOf);

    COMMIT;

    SELECT MetricKey, People = COUNT(*), Refreshed = MAX(RefreshedUtc)
    FROM sel.EmployeeMetric GROUP BY MetricKey ORDER BY MetricKey;
END
GO
PRINT '  sel.usp_Metric_Refresh            applied';
GO

PRINT '== 03_evidence complete ==============================================';
GO
