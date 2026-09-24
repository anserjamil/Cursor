/* =====================================================================================
   11_stage.sql  —  the operational cycle
   -------------------------------------------------------------------------------------
   The stage screens are the core of the product.  One procedure serves Identify, Review
   and Calibration so the three cannot drift apart: sel.fn_CandidateBox decides which
   funnel box a person is in, sel.FunnelPill says what that box is called and how it is
   grouped, and sel.usp_Stage_Candidates returns the rows, the funnel counts and the true
   total in one call.

   Every read joins sec.fn_UserOrgScope — including the drilldown behind every count.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 11_stage ==========================================================';
GO

/* --- sel.StagePerformer ---------------------------------------------------------
   Who may perform a stage: the managed management-level list behind the modal, with a
   usage count so removing a title shows what it costs.                               */
IF OBJECT_ID('sel.StagePerformer') IS NULL
BEGIN
    CREATE TABLE sel.StagePerformer
    (
        StagePerformerId int         IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_StagePerformer PRIMARY KEY,
        LevelValueId int             NOT NULL CONSTRAINT FK_sel_StagePerformer_Value REFERENCES cfg.DomainValue(DomainValueId),
        IsActive     bit             NOT NULL CONSTRAINT DF_sel_StagePerformer_Active DEFAULT (1),
        SortOrder    int             NOT NULL CONSTRAINT DF_sel_StagePerformer_Sort   DEFAULT (0),
        CONSTRAINT UQ_sel_StagePerformer UNIQUE (LevelValueId)
    );
    PRINT '  sel.StagePerformer                created';
END
ELSE PRINT '  sel.StagePerformer                skipped';
GO

/* --- sel.CandidateSource --------------------------------------------------------
   ELIGIBLE | EXISTING POOL | OUTSIDE CRITERIA, per cycle and person.  The snapshot in
   sel.CycleCandidate carries the source it was resolved with; this table records any
   later change of source (a Non HIPO pull, an add-people outside criteria) without
   rewriting the snapshot.                                                            */
IF OBJECT_ID('sel.CandidateSource') IS NULL
BEGIN
    CREATE TABLE sel.CandidateSource
    (
        CandidateSourceId bigint     IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CandidateSource PRIMARY KEY,
        CycleId     int           NOT NULL CONSTRAINT FK_sel_CSrc_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo nvarchar(30)  NOT NULL,
        SourceCode  nvarchar(30)  NOT NULL,
        Note        nvarchar(400) NULL,
        AddedByLogin nvarchar(128) NULL,
        AddedOnUtc  datetime2(3)  NOT NULL CONSTRAINT DF_sel_CSrc_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_CandidateSource UNIQUE (CycleId, PersonnelNo, SourceCode)
    );
    PRINT '  sel.CandidateSource               created';
END
ELSE PRINT '  sel.CandidateSource               skipped';
GO

/* --- sel.CandidateFlag ----------------------------------------------------------
   The also-in-other-cycles cache, rebuilt on open.                                   */
IF OBJECT_ID('sel.CandidateFlag') IS NULL
BEGIN
    CREATE TABLE sel.CandidateFlag
    (
        CandidateFlagId bigint     IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CandidateFlag PRIMARY KEY,
        PersonnelNo  nvarchar(30) NOT NULL,
        CycleId      int          NOT NULL,
        OtherCycleId int          NOT NULL,
        RebuiltOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sel_CandidateFlag_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_CandidateFlag UNIQUE (CycleId, PersonnelNo, OtherCycleId)
    );
    CREATE INDEX IX_sel_CandidateFlag ON sel.CandidateFlag (CycleId, PersonnelNo);
    PRINT '  sel.CandidateFlag                 created';
END
ELSE PRINT '  sel.CandidateFlag                 skipped';
GO

/* --- sel.SuccessionPlanRow ------------------------------------------------------
   A plan is a person x department x level x year.  A person may be planned in several
   departments, so the key includes the department.                                    */
IF OBJECT_ID('sel.SuccessionPlanRow') IS NULL
BEGIN
    CREATE TABLE sel.SuccessionPlanRow
    (
        SuccessionPlanRowId bigint  IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_SuccessionPlanRow PRIMARY KEY,
        CycleId      int           NOT NULL CONSTRAINT FK_sel_SPR_Cycle REFERENCES sel.Cycle(CycleId),
        CycleProcessId int         NULL CONSTRAINT FK_sel_SPR_Process REFERENCES sel.CycleProcess(CycleProcessId),
        PersonnelNo  nvarchar(30)  NOT NULL,
        Department   nvarchar(200) NOT NULL,
        OrgCode      nvarchar(40)  NULL,
        LevelCode    nvarchar(20)  NULL,
        PlanYear     smallint      NOT NULL,
        Remark       nvarchar(600) NULL,
        ActorLogin   nvarchar(128) NOT NULL,
        DecidedOnUtc datetime2(3)  NOT NULL CONSTRAINT DF_sel_SPR_On DEFAULT (SYSUTCDATETIME()),
        IsDropped    bit           NOT NULL CONSTRAINT DF_sel_SPR_Dropped DEFAULT (0),
        CONSTRAINT UQ_sel_SuccessionPlanRow UNIQUE (CycleId, PersonnelNo, Department, PlanYear)
    );
    CREATE INDEX IX_sel_SPR_Cycle ON sel.SuccessionPlanRow (CycleId, IsDropped) INCLUDE (PersonnelNo, Department, LevelCode);
    PRINT '  sel.SuccessionPlanRow             created';
END
ELSE PRINT '  sel.SuccessionPlanRow             skipped';
GO

/* --- sel.SuccessionSlot ---------------------------------------------------------
   The by-position view: a position, a named successor, a readiness level and a remark. */
IF OBJECT_ID('sel.SuccessionSlot') IS NULL
BEGIN
    CREATE TABLE sel.SuccessionSlot
    (
        SuccessionSlotId bigint     IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_SuccessionSlot PRIMARY KEY,
        CycleId      int           NOT NULL CONSTRAINT FK_sel_SSlot_Cycle REFERENCES sel.Cycle(CycleId),
        PositionCode nvarchar(60)  NOT NULL,
        IncumbentPersonnelNo nvarchar(30) NULL,
        SuccessorPersonnelNo nvarchar(30) NOT NULL,
        LevelCode    nvarchar(20)  NULL,
        Remark       nvarchar(600) NULL,
        OrgCode      nvarchar(40)  NULL,
        ActorLogin   nvarchar(128) NOT NULL,
        DecidedOnUtc datetime2(3)  NOT NULL CONSTRAINT DF_sel_SSlot_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_SuccessionSlot UNIQUE (CycleId, PositionCode, SuccessorPersonnelNo)
    );
    CREATE INDEX IX_sel_SSlot_Cycle ON sel.SuccessionSlot (CycleId, PositionCode);
    PRINT '  sel.SuccessionSlot                created';
END
ELSE PRINT '  sel.SuccessionSlot                skipped';
GO

/* --- sel.ReadinessHistory -------------------------------------------------------
   Person x year x level, for the level-history strip.                                */
IF OBJECT_ID('sel.ReadinessHistory') IS NULL
BEGIN
    CREATE TABLE sel.ReadinessHistory
    (
        ReadinessHistoryId bigint   IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_ReadinessHistory PRIMARY KEY,
        PersonnelNo nvarchar(30) NOT NULL,
        HistoryYear smallint     NOT NULL,
        LevelCode   nvarchar(20) NULL,
        CycleId     int          NULL,
        RecordedOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sel_RH_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_ReadinessHistory UNIQUE (PersonnelNo, HistoryYear, CycleId)
    );
    CREATE INDEX IX_sel_RH_Person ON sel.ReadinessHistory (PersonnelNo, HistoryYear DESC);
    PRINT '  sel.ReadinessHistory              created';
END
ELSE PRINT '  sel.ReadinessHistory              skipped';
GO

/* --- sel.ColumnCatalog ----------------------------------------------------------
   The ~200-column employee record, grouped and searchable, behind the column picker. */
IF OBJECT_ID('sel.ColumnCatalog') IS NULL
BEGIN
    CREATE TABLE sel.ColumnCatalog
    (
        ColumnCatalogId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_ColumnCatalog PRIMARY KEY,
        ColumnName   nvarchar(128) NOT NULL CONSTRAINT UQ_sel_ColumnCatalog UNIQUE,
        Caption      nvarchar(160) NOT NULL,
        GroupName    nvarchar(80)  NOT NULL CONSTRAINT DF_sel_ColumnCatalog_Grp DEFAULT (N'Roster'),
        DataType     nvarchar(20)  NOT NULL,
        /* A sensitive column is readable on a record but refused as a filter. */
        IsSensitive  bit           NOT NULL CONSTRAINT DF_sel_ColumnCatalog_Sens DEFAULT (0),
        IsDefault    bit           NOT NULL CONSTRAINT DF_sel_ColumnCatalog_Def  DEFAULT (0),
        SortOrder    int           NOT NULL CONSTRAINT DF_sel_ColumnCatalog_Sort DEFAULT (0),
        IsPresent    bit           NOT NULL CONSTRAINT DF_sel_ColumnCatalog_Pres DEFAULT (1)
    );
    PRINT '  sel.ColumnCatalog                 created';
END
ELSE PRINT '  sel.ColumnCatalog                 skipped';
GO

/* --- sel.SavedView --------------------------------------------------------------
   A per-user column set per screen, and the administrator's preset.                  */
IF OBJECT_ID('sel.SavedView') IS NULL
BEGIN
    CREATE TABLE sel.SavedView
    (
        SavedViewId  int            IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_SavedView PRIMARY KEY,
        LoginName    nvarchar(128)  NULL,          -- NULL together with IsPreset = 1 is the shared default
        ScreenCode   nvarchar(160)  NOT NULL,
        ViewName     nvarchar(120)  NOT NULL CONSTRAINT DF_sel_SavedView_Name DEFAULT (N'Default'),
        ColumnList   nvarchar(max)  NOT NULL,      -- comma separated column names, in order
        SortBy       nvarchar(128)  NULL,
        SortDir      nvarchar(4)    NULL,
        IsPreset     bit            NOT NULL CONSTRAINT DF_sel_SavedView_Preset DEFAULT (0),
        SavedOnUtc   datetime2(3)   NOT NULL CONSTRAINT DF_sel_SavedView_On DEFAULT (SYSUTCDATETIME())
    );
    CREATE UNIQUE INDEX UX_sel_SavedView_User
        ON sel.SavedView (LoginName, ScreenCode, ViewName) WHERE LoginName IS NOT NULL;
    CREATE UNIQUE INDEX UX_sel_SavedView_Preset
        ON sel.SavedView (ScreenCode) WHERE IsPreset = 1 AND LoginName IS NULL;
    PRINT '  sel.SavedView                     created';
END
ELSE PRINT '  sel.SavedView                     skipped';
GO

/* --- sel.FunnelPill -------------------------------------------------------------
   One row of pills shared by Identify, Review and Calibration.  The caption, the
   tooltip that explains it, the group it sits in and whether it is the outcome pill
   are all data, so the three stages cannot drift apart.                              */
IF OBJECT_ID('sel.FunnelPill') IS NULL
BEGIN
    CREATE TABLE sel.FunnelPill
    (
        FunnelPillId  int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_FunnelPill PRIMARY KEY,
        StageKindCode nvarchar(30)  NOT NULL CONSTRAINT FK_sel_FunnelPill_Kind REFERENCES sel.StageKind(StageKindCode),
        PillCode      nvarchar(40)  NOT NULL,
        Caption       nvarchar(120) NOT NULL,
        Tooltip       nvarchar(400) NULL,
        GroupNo       int           NOT NULL CONSTRAINT DF_sel_FunnelPill_Grp DEFAULT (1),
        SemanticRole  nvarchar(40)  NULL,
        /* The outcome pill is solid ink, and is a sum rather than a box. */
        IsOutcome     bit           NOT NULL CONSTRAINT DF_sel_FunnelPill_Out   DEFAULT (0),
        CountsToTotal bit           NOT NULL CONSTRAINT DF_sel_FunnelPill_Total DEFAULT (0),
        SortOrder     int           NOT NULL CONSTRAINT DF_sel_FunnelPill_Sort  DEFAULT (0),
        CONSTRAINT UQ_sel_FunnelPill UNIQUE (StageKindCode, PillCode)
    );
    PRINT '  sel.FunnelPill                    created';
END
ELSE PRINT '  sel.FunnelPill                    skipped';
GO

/* =====================================================================================
   Which box a person is in
   -------------------------------------------------------------------------------------
   One function, three stages.  Deciding moves a person out of their source box into the
   decision box; nobody is "kept" by hand in Review, because everyone there is nominated
   until changed.
   ===================================================================================== */
CREATE OR ALTER FUNCTION sel.fn_CandidateBox
(
    @StageKindCode nvarchar(30),
    @DecisionCode  nvarchar(60),    -- NULL when no decision has been taken in this stage
    @SourceCode    nvarchar(30)
)
RETURNS nvarchar(40)
AS
BEGIN
    /* A cleared decision is the same as no decision. */
    IF @DecisionCode = N'NONE' SET @DecisionCode = NULL;

    /* Watch and drop read the same in every stage. */
    IF @DecisionCode = N'WATCH'   RETURN N'WATCH';
    IF @DecisionCode = N'DROPPED' RETURN N'DROPPED';

    IF @StageKindCode IN (N'TR_IDENTIFY', N'SU_IDENTIFY', N'DV_IDENTIFY')
    BEGIN
        IF @DecisionCode IN (N'NOMINATED', N'KEPT') RETURN N'NEW_NOMINATIONS';
        IF @DecisionCode = N'ACTIVITY'              RETURN N'NEW_NOMINATIONS';
        IF @SourceCode = N'EXISTING POOL'           RETURN N'EXISTING_POOL';
        RETURN N'ELIGIBLE';
    END;

    IF @StageKindCode IN (N'TR_REVIEW', N'SU_REVIEW', N'DV_REVIEW')
    BEGIN
        /* Nobody is kept by hand: everyone in Review is nominated until changed. */
        IF @SourceCode = N'EXISTING POOL' AND @DecisionCode IS NULL RETURN N'EXISTING_POOL';
        RETURN N'NEW_NOMINATIONS';
    END;

    IF @StageKindCode IN (N'TR_CALIBRATE', N'SU_CALIBRATE')
    BEGIN
        IF @DecisionCode IN (N'VP_VERY_STRONG', N'DIR_VERY_STRONG', N'DIR_STRONG', N'MGR_STRONG')
            RETURN @DecisionCode;
        IF @SourceCode = N'EXISTING POOL' AND @DecisionCode IS NULL RETURN N'EXISTING_POOL';
        RETURN N'NEW_NOMINATIONS';
    END;

    RETURN N'NEW_NOMINATIONS';
END
GO
PRINT '  sel.fn_CandidateBox               applied';
GO

/* sel.usp_Stage_State — future / open / closed / undated against the as-of date, with
   the lock message that says exactly why, and which stage is open now.                */
CREATE OR ALTER PROCEDURE sel.usp_Stage_State
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @AsOf         date = NULL,
    @TestMode     bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    SELECT s.CycleStageId, s.CycleProcessId, p.CycleId, s.StageKindCode, sk.RouteKey, sk.ScreenCode,
           s.Name AS StageName, p.Name AS ProcessName, p.ProcessTypeCode,
           s.StartDate, s.EndDate, s.PerformerLevelValueId,
           PerformerName = pv.Name,
           StageState = sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode),
           /* Read and write are separate questions: an open stage a read-only viewer may
              look at is still read-only. */
           CanWrite = CONVERT(bit, CASE WHEN sec.fn_IsReadOnlyUser(@LoginName) = 1 THEN 0
                           WHEN sel.fn_CycleStatusCode(p.CycleId) <> N'ACTIVE' THEN 0
                           WHEN sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode) <> N'OPEN' THEN 0
                           WHEN sec.fn_ScreenAccess(@LoginName, sk.ScreenCode) < 2 THEN 0
                           ELSE 1 END),
           /* The lock message explains why, and which stage is open now. */
           LockReason =
               CASE WHEN sec.fn_IsReadOnlyUser(@LoginName) = 1 THEN cfg.fn_Message(N'READONLY_REFUSAL')
                    WHEN sel.fn_CycleStatusCode(p.CycleId) = N'CLOSED' THEN cfg.fn_Message(N'CLOSED_CYCLE')
                    WHEN sec.fn_ScreenAccess(@LoginName, sk.ScreenCode) < 2 THEN cfg.fn_Message(N'READONLY_REFUSAL')
                    WHEN sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode) = N'CLOSED'
                         THEN REPLACE(cfg.fn_Message(N'STAGE_CLOSED'), N'{date}', CONVERT(nvarchar(10), s.EndDate, 23))
                    WHEN sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode) = N'FUTURE'
                         THEN REPLACE(cfg.fn_Message(N'STAGE_FUTURE'), N'{date}', CONVERT(nvarchar(10), s.StartDate, 23))
                    WHEN sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode) = N'UNDATED'
                         THEN cfg.fn_Message(N'STAGE_UNDATED')
                    ELSE NULL END,
           OpenStageName = (SELECT TOP (1) s2.Name FROM sel.CycleStage s2
                            JOIN sel.CycleProcess p2 ON p2.CycleProcessId = s2.CycleProcessId
                            WHERE p2.CycleId = p.CycleId
                              AND sel.fn_StageState(s2.CycleStageId, @AsOf, 0) = N'OPEN'
                            ORDER BY p2.SortOrder, s2.SortOrder),
           IsTestMode = @TestMode,
           AsOf = @AsOf
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = s.PerformerLevelValueId
    WHERE s.CycleStageId = @CycleStageId;

    /* The whole tab strip: every stage of every process, with its window and state. */
    SELECT p.CycleProcessId, p.Name AS ProcessName, p.SortOrder AS ProcessSort,
           s.CycleStageId, s.Name AS StageName, sk.RouteKey, s.StartDate, s.EndDate, s.SortOrder,
           StageState = sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode),
           IsCurrent = CONVERT(bit, CASE WHEN s.CycleStageId = @CycleStageId THEN 1 ELSE 0 END)
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE p.CycleId = @cycleId
    ORDER BY p.SortOrder, s.SortOrder;
END
GO
PRINT '  sel.usp_Stage_State               applied';
GO

/* =====================================================================================
   sel.usp_Stage_Candidates — the table, the funnel and the total, in one call
   -------------------------------------------------------------------------------------
   Paged, filtered, sorted and scoped in SQL.  Never .Skip() in C#, and never a filter
   applied to what is already on screen.

   @ColumnSet and @FilterJson may only name columns that exist in sel.ColumnCatalog and
   are not sensitive, so a column name can never arrive from a request into the SQL.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Stage_Candidates
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @PillCode     nvarchar(40) = NULL,     -- clicking a pill filters the table
    @Search       nvarchar(200) = NULL,
    @ColumnSet    nvarchar(max) = NULL,    -- comma separated, from the column picker
    @FilterJson   nvarchar(max) = NULL,    -- [{"field":"GradeCode","values":["12","13"]}]
    @SortBy       nvarchar(128) = NULL,
    @SortDir      nvarchar(4) = N'ASC',
    @PageNo       int = 1,
    @PageSize     int = NULL,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
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

    DECLARE @cycleId int, @stageKind nvarchar(30), @processId int;
    SELECT @cycleId = p.CycleId, @stageKind = s.StageKindCode, @processId = s.CycleProcessId
    FROM sel.CycleStage s JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That stage no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        SELECT TOP (0) CAST(NULL AS nvarchar(40)) AS PillCode;
        SELECT TotalRows = CAST(NULL AS int), ShownRows = 0, PoolCount = CAST(NULL AS int);
        RETURN;
    END;

    /* --- everyone this stage is working on, with their box ------------------------ */
    CREATE TABLE #cand
    (
        PersonnelNo  nvarchar(30) NOT NULL PRIMARY KEY,
        SourceCode   nvarchar(30) NOT NULL,
        DecisionCode nvarchar(60) NULL,
        BoxCode      nvarchar(40) NOT NULL,
        OrgCode      nvarchar(40) NOT NULL
    );

    INSERT #cand (PersonnelNo, SourceCode, DecisionCode, BoxCode, OrgCode)
    SELECT cc.PersonnelNo,
           src.SourceCode,
           d.DecisionCode,
           sel.fn_CandidateBox(@stageKind, d.DecisionCode, src.SourceCode),
           cc.OrgCode
    FROM sel.CycleCandidate cc
    /* Every read joins the viewer's organisation scope. */
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    CROSS APPLY (
        /* The latest source wins: a later Non HIPO pull or outside-criteria add replaces
           the one the snapshot was resolved with. */
        SELECT TOP (1) SourceCode FROM (
            SELECT cc.SourceCode, Ord = 0
            UNION ALL
            SELECT cs.SourceCode, 1 FROM sel.CandidateSource cs
            WHERE cs.CycleId = cc.CycleId AND cs.PersonnelNo = cc.PersonnelNo
        ) z ORDER BY Ord DESC
    ) src
    OUTER APPLY (
        SELECT TOP (1) DecisionCode = dv.ValueCode
        FROM sel.CandidateDecision cd
        JOIN cfg.DomainValue dv ON dv.DomainValueId = cd.DecisionValueId
        WHERE cd.CycleStageId = @CycleStageId AND cd.PersonnelNo = cc.PersonnelNo
        ORDER BY cd.DecisionId DESC
    ) d
    WHERE cc.CycleId = @cycleId;

    /* --- the funnel: counts per pill, then the outcome as a sum ------------------- */
    SELECT fp.FunnelPillId, fp.PillCode, fp.Caption, fp.Tooltip, fp.GroupNo,
           fp.SemanticRole, fp.IsOutcome, fp.CountsToTotal, fp.SortOrder,
           Cnt = CASE WHEN fp.IsOutcome = 1
                      THEN (SELECT COUNT(*) FROM #cand c
                            WHERE c.BoxCode IN (SELECT PillCode FROM sel.FunnelPill
                                                WHERE StageKindCode = @stageKind AND CountsToTotal = 1))
                      ELSE (SELECT COUNT(*) FROM #cand c WHERE c.BoxCode = fp.PillCode) END
    FROM sel.FunnelPill fp
    WHERE fp.StageKindCode = @stageKind
    ORDER BY fp.GroupNo, fp.SortOrder;

    /* --- the rows ----------------------------------------------------------------- */
    /* Only columns the catalogue knows, and never a sensitive one as a filter. */
    DECLARE @cols TABLE (ColumnName nvarchar(128), Ord int IDENTITY(1,1));
    IF @ColumnSet IS NOT NULL
        INSERT @cols (ColumnName)
        SELECT cc.ColumnName
        FROM STRING_SPLIT(@ColumnSet, N',') s
        JOIN sel.ColumnCatalog cc ON cc.ColumnName = LTRIM(RTRIM(s.value))
        WHERE cc.IsPresent = 1;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'ROSTER');
    DECLARE @keyCol nvarchar(128) = (SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'ROSTER');

    DECLARE @extraCols nvarchar(max) = N'';
    IF @obj IS NOT NULL AND EXISTS (SELECT 1 FROM @cols)
        SELECT @extraCols = @extraCols + N', rs.' + QUOTENAME(ColumnName)
        FROM @cols ORDER BY Ord;

    /* Column filters: values come from a procedure with counts, and combine. */
    DECLARE @filterSql nvarchar(max) = N'';
    IF @FilterJson IS NOT NULL AND @obj IS NOT NULL
    BEGIN
        DECLARE @badFilter nvarchar(128);
        SELECT TOP (1) @badFilter = j.field
        FROM OPENJSON(@FilterJson) WITH (field nvarchar(128) N'$.field') j
        LEFT JOIN sel.ColumnCatalog cc ON cc.ColumnName = j.field
        WHERE cc.ColumnName IS NULL OR cc.IsSensitive = 1;

        IF @badFilter IS NOT NULL
        BEGIN
            /* Sensitive columns are readable on a record but refused as filters, and
               the refusal says why. */
            SET @Problem = CASE WHEN EXISTS (SELECT 1 FROM sel.ColumnCatalog WHERE ColumnName = @badFilter AND IsSensitive = 1)
                                THEN cfg.fn_Message(N'SENSITIVE_FILTER')
                                ELSE N'"' + @badFilter + N'" is not a column of the employee record.' END;
            SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
            SELECT TotalRows = CAST(NULL AS int), ShownRows = 0, PoolCount = (SELECT COUNT(*) FROM #cand);
            DROP TABLE #cand; RETURN;
        END;

        SELECT @filterSql = @filterSql + N' AND rs.' + QUOTENAME(j.field) + N' IN ('
             + ISNULL(STUFF((SELECT N', ' + cfg.fn_EscapeLiteral(v.value)
                             FROM OPENJSON(j.vals) v
                             FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N''), N'NULL') + N')'
        FROM OPENJSON(@FilterJson)
             WITH (field nvarchar(128) N'$.field', vals nvarchar(max) N'$.values' AS JSON) j;
    END;

    /* The sort column must also be one the catalogue knows. */
    DECLARE @orderSql nvarchar(400) = N'e.FullName ASC';
    IF @SortBy IS NOT NULL
    BEGIN
        IF @SortBy IN (N'FullName', N'PersonnelNo', N'OrgName', N'JobTitle', N'GradeCode', N'BoxCode')
            SET @orderSql = CASE @SortBy
                                 WHEN N'OrgName' THEN N'o.Name'
                                 WHEN N'BoxCode' THEN N'c.BoxCode'
                                 ELSE N'e.' + QUOTENAME(@SortBy) END + N' ' + @SortDir;
        ELSE IF @obj IS NOT NULL AND EXISTS (SELECT 1 FROM sel.ColumnCatalog WHERE ColumnName = @SortBy AND IsPresent = 1)
            SET @orderSql = N'rs.' + QUOTENAME(@SortBy) + N' ' + @SortDir;
    END;

    DECLARE @rosterJoin nvarchar(max) =
        CASE WHEN @obj IS NULL THEN N''
             ELSE N' LEFT JOIN ' + @obj + N' rs ON CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol)
                + N') = c.PersonnelNo' END;

    DECLARE @sql nvarchar(max) = N'
    SELECT c.PersonnelNo, e.FullName, c.OrgCode, o.Name AS OrgName, e.JobTitle, e.GradeCode,
           e.PermJobSuffix, e.PermJobSuffixDesc, e.ManagementLevelCode,
           c.SourceCode, c.DecisionCode, c.BoxCode,
           DecisionName = dv.Name, DecisionRole = dv.SemanticRole,
           SourceName   = sv.Name, SourceRole   = sv.SemanticRole,
           AlsoInCount  = (SELECT COUNT(*) FROM sel.CandidateFlag f
                           WHERE f.CycleId = @cycleId AND f.PersonnelNo = c.PersonnelNo)'
        + @extraCols + N'
    FROM #cand c
    JOIN sel.Employee e ON e.PersonnelNo = c.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = c.OrgCode
    LEFT JOIN cfg.DomainValue dv ON dv.DomainValueId = cfg.fn_DomainValueId(N''DECISION'', c.DecisionCode)
    LEFT JOIN cfg.DomainValue sv ON sv.DomainValueId = cfg.fn_DomainValueId(N''CANDIDATE_SOURCE'', c.SourceCode)'
        + @rosterJoin + N'
    WHERE (@PillCode IS NULL OR c.BoxCode = @PillCode)
      AND (@Search IS NULL OR e.FullName LIKE N''%'' + @Search + N''%''
           OR c.PersonnelNo LIKE N''%'' + @Search + N''%''
           OR e.JobTitle LIKE N''%'' + @Search + N''%''
           OR o.Name LIKE N''%'' + @Search + N''%'')'
        + @filterSql + N'
    ORDER BY ' + @orderSql + N'
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;';

    DECLARE @countSql nvarchar(max) = N'
    SELECT TotalRows = COUNT(*)
    FROM #cand c
    JOIN sel.Employee e ON e.PersonnelNo = c.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = c.OrgCode'
        + @rosterJoin + N'
    WHERE (@PillCode IS NULL OR c.BoxCode = @PillCode)
      AND (@Search IS NULL OR e.FullName LIKE N''%'' + @Search + N''%''
           OR c.PersonnelNo LIKE N''%'' + @Search + N''%''
           OR e.JobTitle LIKE N''%'' + @Search + N''%''
           OR o.Name LIKE N''%'' + @Search + N''%'')'
        + @filterSql + N';';

    DECLARE @params nvarchar(400) =
        N'@cycleId int, @PillCode nvarchar(40), @Search nvarchar(200), @PageNo int, @PageSize int';

    DECLARE @total int;
    BEGIN TRY
        EXEC sp_executesql @sql, @params,
             @cycleId = @cycleId, @PillCode = @PillCode, @Search = @Search,
             @PageNo = @PageNo, @PageSize = @PageSize;

        DECLARE @cntOut nvarchar(max) = REPLACE(@countSql, N'SELECT TotalRows = COUNT(*)', N'SELECT @total = COUNT(*)');
        EXEC sp_executesql @cntOut, N'@cycleId int, @PillCode nvarchar(40), @Search nvarchar(200), @total int OUTPUT',
             @cycleId = @cycleId, @PillCode = @PillCode, @Search = @Search, @total = @total OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Problem = N'This list could not be read: ' + ERROR_MESSAGE();
        SELECT TotalRows = CAST(NULL AS int), ShownRows = 0, PoolCount = (SELECT COUNT(*) FROM #cand);
        DROP TABLE #cand; RETURN;
    END CATCH;

    /* The true total in the header: "240 shown of 12,480". */
    SELECT TotalRows = @total,
           ShownRows = CASE WHEN @total < @PageSize THEN @total ELSE @PageSize END,
           PoolCount = (SELECT COUNT(*) FROM #cand),
           PageNo = @PageNo, PageSize = @PageSize,
           MaxDraw = cfg.fn_SettingNum(N'STAGE_LIST_MAX_DRAW');

    DROP TABLE #cand;
END
GO
PRINT '  sel.usp_Stage_Candidates          applied';
GO

/* sel.usp_Stage_Funnel — the funnel on its own, for the live count refresh. */
CREATE OR ALTER PROCEDURE sel.usp_Stage_Funnel
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @p nvarchar(400);
    EXEC sel.usp_Stage_Candidates @LoginName = @LoginName, @CycleStageId = @CycleStageId,
         @AsOf = @AsOf, @PageSize = 1, @Problem = @p OUTPUT;
END
GO
PRINT '  sel.usp_Stage_Funnel              applied';
GO

/* sel.usp_Stage_ColumnValues — a column filter's value list, with counts.  The values
   come from a procedure, not from what is on screen.                                  */
CREATE OR ALTER PROCEDURE sel.usp_Stage_ColumnValues
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @ColumnName   nvarchar(128),
    @Search       nvarchar(200) = NULL,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @isSensitive bit, @present bit;
    SELECT @isSensitive = IsSensitive, @present = IsPresent
    FROM sel.ColumnCatalog WHERE ColumnName = @ColumnName;

    IF @present IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@ColumnName, N'') + N'" is not a column of the employee record.';
        SELECT TOP (0) CAST(NULL AS nvarchar(400)) AS [Value]; RETURN;
    END;
    IF @isSensitive = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'SENSITIVE_FILTER');
        SELECT TOP (0) CAST(NULL AS nvarchar(400)) AS [Value]; RETURN;
    END;

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);
    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'ROSTER');
    DECLARE @keyCol nvarchar(128) = (SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'ROSTER');

    IF @obj IS NULL
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS nvarchar(400)) AS [Value]; RETURN;
    END;

    DECLARE @sql nvarchar(max) = N'
        SELECT [Value] = CONVERT(nvarchar(400), rs.' + QUOTENAME(@ColumnName) + N'),
               Cnt = COUNT(*)
        FROM sel.CycleCandidate cc
        JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
        JOIN ' + @obj + N' rs ON CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol) + N') = cc.PersonnelNo
        WHERE cc.CycleId = @cycleId
          AND (@Search IS NULL OR CONVERT(nvarchar(400), rs.' + QUOTENAME(@ColumnName) + N') LIKE N''%'' + @Search + N''%'')
        GROUP BY CONVERT(nvarchar(400), rs.' + QUOTENAME(@ColumnName) + N')
        ORDER BY COUNT(*) DESC, 1;';

    BEGIN TRY
        EXEC sp_executesql @sql, N'@LoginName nvarchar(128), @cycleId int, @Search nvarchar(200)',
             @LoginName = @LoginName, @cycleId = @cycleId, @Search = @Search;
    END TRY
    BEGIN CATCH
        SET @Problem = N'That column could not be read: ' + ERROR_MESSAGE();
        SELECT TOP (0) CAST(NULL AS nvarchar(400)) AS [Value];
    END CATCH;
END
GO
PRINT '  sel.usp_Stage_ColumnValues        applied';
GO

/* =====================================================================================
   Decisions
   ===================================================================================== */

/* sel.usp_Decision_Save — single and bulk, through one table-valued parameter.  Never a
   loop of single calls from C#.                                                        */
CREATE OR ALTER PROCEDURE sel.usp_Decision_Save
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30) = NULL,
    @People       dbo.IdList READONLY,
    @DecisionCode nvarchar(60),
    @Reason       nvarchar(600) = NULL,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @processId int, @stageKind nvarchar(30), @screenCode nvarchar(160),
            @performerId int;
    SELECT @cycleId = p.CycleId, @processId = s.CycleProcessId, @stageKind = s.StageKindCode,
           @screenCode = sk.ScreenCode, @performerId = s.PerformerLevelValueId
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That stage no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* 1 — authority.  An auditor reads this screen and changes nothing. */
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1 OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF sel.fn_CycleStatusCode(@cycleId) = N'CLOSED'
    BEGIN
        SET @Problem = cfg.fn_Message(N'CLOSED_CYCLE');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* Only the open stage accepts writes, unless test mode. */
    DECLARE @state nvarchar(20) = sel.fn_StageState(@CycleStageId, @AsOf, @TestMode);
    IF @state <> N'OPEN'
    BEGIN
        SET @Problem = CASE @state
            WHEN N'CLOSED'  THEN REPLACE(cfg.fn_Message(N'STAGE_CLOSED'), N'{date}',
                                 CONVERT(nvarchar(10), (SELECT EndDate FROM sel.CycleStage WHERE CycleStageId = @CycleStageId), 23))
            WHEN N'FUTURE'  THEN REPLACE(cfg.fn_Message(N'STAGE_FUTURE'), N'{date}',
                                 CONVERT(nvarchar(10), (SELECT StartDate FROM sel.CycleStage WHERE CycleStageId = @CycleStageId), 23))
            ELSE cfg.fn_Message(N'STAGE_UNDATED') END;
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* Test mode is an administrator's tool. */
    IF @TestMode = 1 AND NOT EXISTS (SELECT 1 FROM sec.AppUser u
                                     JOIN sec.UserRole ur ON ur.AppUserId = u.AppUserId
                                     JOIN sec.Role r ON r.RoleId = ur.RoleId
                                     WHERE u.LoginName = @LoginName AND r.RoleCode = N'ADMIN')
    BEGIN
        SET @Problem = N'Test mode is available to administrators only.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* 2 — the decision word must be one this application knows. */
    DECLARE @decisionId int = cfg.fn_DomainValueId(N'DECISION', @DecisionCode);
    IF @decisionId IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@DecisionCode, N'') + N'" is not a decision this application records.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* Watch and drop in review and calibration ask for a reason, and the prompt says so. */
    IF @DecisionCode IN (N'WATCH', N'DROPPED')
       AND @stageKind IN (N'TR_REVIEW', N'TR_CALIBRATE', N'SU_REVIEW', N'SU_CALIBRATE')
       AND NULLIF(LTRIM(RTRIM(ISNULL(@Reason, N''))), N'') IS NULL
    BEGIN
        SET @Problem = N'This decision needs a reason, so the log can explain it later.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* The people to decide on: one, or a table-valued list. */
    CREATE TABLE #who (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    IF @PersonnelNo IS NOT NULL INSERT #who VALUES (@PersonnelNo);
    INSERT #who SELECT Id FROM @People WHERE Id NOT IN (SELECT PersonnelNo FROM #who);

    /* Only people in this cycle's pool, and only inside the viewer's scope. */
    DELETE w FROM #who w
    WHERE NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                      JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
                      WHERE cc.CycleId = @cycleId AND cc.PersonnelNo = w.PersonnelNo);

    IF NOT EXISTS (SELECT 1 FROM #who)
    BEGIN
        SET @Problem = N'Nobody in your organisations was selected, so nothing was changed.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        DROP TABLE #who; RETURN;
    END;

    BEGIN TRAN;

    /* Append only: the current decision is the latest row, so every change — including
       clearing — is in the log and nothing is overwritten. */
    INSERT sel.CandidateDecision (CycleId, CycleProcessId, CycleStageId, PersonnelNo,
                                  DecisionValueId, Reason, PerformerLevelValueId,
                                  ActorLogin, IsTest, OrgCode)
    SELECT @cycleId, @processId, @CycleStageId, w.PersonnelNo, @decisionId, @Reason,
           @performerId, @LoginName, @TestMode, cc.OrgCode
    FROM #who w
    JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = w.PersonnelNo;

    DECLARE @n int = @@ROWCOUNT;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleStageId) + N'/' + CONVERT(nvarchar(10), @n) + N' people';
    EXEC audit.usp_Log @TableName = N'sel.CandidateDecision', @KeyText = @keyText,
                       @ActionCode = @DecisionCode, @AfterJson = @Reason, @LoginName = @LoginName;

    /* What changed, so the caller can refresh those rows and the funnel. */
    SELECT w.PersonnelNo, e.FullName,
           DecisionCode = @DecisionCode,
           DecisionName = (SELECT Name FROM cfg.DomainValue WHERE DomainValueId = @decisionId),
           BoxCode = sel.fn_CandidateBox(@stageKind, @DecisionCode,
                       (SELECT TOP (1) SourceCode FROM sel.CycleCandidate
                        WHERE CycleId = @cycleId AND PersonnelNo = w.PersonnelNo)),
           IsTest = @TestMode
    FROM #who w JOIN sel.Employee e ON e.PersonnelNo = w.PersonnelNo;

    DROP TABLE #who;
END
GO
PRINT '  sel.usp_Decision_Save             applied';
GO

/* sel.usp_Decision_Clear — watch, drop, nominate and calibrate can all be cleared, and
   clearing is itself logged.                                                            */
CREATE OR ALTER PROCEDURE sel.usp_Decision_Clear
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30) = NULL,
    @People       dbo.IdList READONLY,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    /* Clearing is a decision word of its own, so it goes through the same door and lands
       in the same log. */
    EXEC sel.usp_Decision_Save @LoginName = @LoginName, @CycleStageId = @CycleStageId,
         @PersonnelNo = @PersonnelNo, @People = @People, @DecisionCode = N'NONE',
         @Reason = NULL, @AsOf = @AsOf, @TestMode = @TestMode, @Problem = @Problem OUTPUT;
END
GO
PRINT '  sel.usp_Decision_Clear            applied';
GO

/* sel.usp_Decision_Log — every user decision as a row, filterable. */
CREATE OR ALTER PROCEDURE sel.usp_Decision_Log
    @LoginName    nvarchar(128),
    @CycleId      int = NULL,
    @CycleStageId int = NULL,
    @PersonnelNo  nvarchar(30) = NULL,
    @DecisionCode nvarchar(60) = NULL,
    @Search       nvarchar(200) = NULL,
    @TestOnly     bit = NULL,
    @PageNo       int = 1,
    @PageSize     int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageNo IS NULL OR @PageNo < 1 SET @PageNo = 1;

    ;WITH x AS
    (
        SELECT d.DecisionId, d.CycleId, d.CycleProcessId, d.CycleStageId, d.PersonnelNo,
               d.Reason, d.ActorLogin, d.DecidedOnUtc, d.IsTest,
               DecisionCode = dv.ValueCode, DecisionName = dv.Name, DecisionRole = dv.SemanticRole,
               PerformerName = pv.Name,
               e.FullName, d.OrgCode, o.Name AS OrgName,
               CycleName = c.Name, CycleCode = c.CycleCode,
               ProcessName = p.Name, StageName = s.Name,
               ActorName = (SELECT TOP (1) u.DisplayName FROM sec.AppUser u WHERE u.LoginName = d.ActorLogin)
        FROM sel.CandidateDecision d
        /* Every read joins the viewer's organisation scope, the log included. */
        JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = d.OrgCode
        JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
        LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = d.PerformerLevelValueId
        LEFT JOIN sel.Employee e ON e.PersonnelNo = d.PersonnelNo
        LEFT JOIN sel.OrgNode o ON o.OrgCode = d.OrgCode
        LEFT JOIN sel.Cycle c ON c.CycleId = d.CycleId
        LEFT JOIN sel.CycleProcess p ON p.CycleProcessId = d.CycleProcessId
        LEFT JOIN sel.CycleStage s ON s.CycleStageId = d.CycleStageId
        WHERE (@CycleId      IS NULL OR d.CycleId = @CycleId)
          AND (@CycleStageId IS NULL OR d.CycleStageId = @CycleStageId)
          AND (@PersonnelNo  IS NULL OR d.PersonnelNo = @PersonnelNo)
          AND (@DecisionCode IS NULL OR dv.ValueCode = @DecisionCode)
          AND (@TestOnly     IS NULL OR d.IsTest = @TestOnly)
          AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
               OR d.PersonnelNo LIKE N'%' + @Search + N'%'
               OR d.Reason LIKE N'%' + @Search + N'%'
               OR d.ActorLogin LIKE N'%' + @Search + N'%')
    )
    SELECT * FROM x
    ORDER BY DecidedOnUtc DESC, DecisionId DESC
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT TotalRows = COUNT(*)
    FROM sel.CandidateDecision d
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = d.OrgCode
    JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
    LEFT JOIN sel.Employee e ON e.PersonnelNo = d.PersonnelNo
    WHERE (@CycleId      IS NULL OR d.CycleId = @CycleId)
      AND (@CycleStageId IS NULL OR d.CycleStageId = @CycleStageId)
      AND (@PersonnelNo  IS NULL OR d.PersonnelNo = @PersonnelNo)
      AND (@DecisionCode IS NULL OR dv.ValueCode = @DecisionCode)
      AND (@TestOnly     IS NULL OR d.IsTest = @TestOnly)
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
           OR d.PersonnelNo LIKE N'%' + @Search + N'%'
           OR d.Reason LIKE N'%' + @Search + N'%'
           OR d.ActorLogin LIKE N'%' + @Search + N'%');

    /* The filter chips: one per decision word, with its count. */
    SELECT DecisionCode = dv.ValueCode, DecisionName = dv.Name, dv.SemanticRole, dv.SortOrder,
           Cnt = COUNT(d.DecisionId)
    FROM cfg.fn_DomainValues(N'DECISION') dv
    LEFT JOIN sel.CandidateDecision d ON d.DecisionValueId = dv.DomainValueId
         AND (@CycleId IS NULL OR d.CycleId = @CycleId)
         AND EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@LoginName) sc WHERE sc.OrgCode = d.OrgCode)
    GROUP BY dv.ValueCode, dv.Name, dv.SemanticRole, dv.SortOrder
    ORDER BY dv.SortOrder;
END
GO
PRINT '  sel.usp_Decision_Log              applied';
GO

/* sel.usp_Candidate_AddPeople — the + Add people modal.  In talent and development cycles
   anyone in the roster may be added, flagged Outside criteria and logged.  In succession
   stages the pull is from the eligible pool as Non HIPO.                                */
CREATE OR ALTER PROCEDURE sel.usp_Candidate_AddPeople
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @People       dbo.IdList READONLY,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @processId int, @stageKind nvarchar(30), @screenCode nvarchar(160),
            @processType nvarchar(30), @performerId int;
    SELECT @cycleId = p.CycleId, @processId = s.CycleProcessId, @stageKind = s.StageKindCode,
           @screenCode = sk.ScreenCode, @processType = p.ProcessTypeCode, @performerId = s.PerformerLevelValueId
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That stage no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1 OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so nobody can be added to it.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* A succession stage pulls from the eligible pool as Non HIPO; everywhere else the
       roster is fair game, and the person is flagged Outside criteria. */
    DECLARE @sourceCode nvarchar(30) =
        CASE WHEN @processType = N'SUCCESSION' THEN N'ELIGIBLE' ELSE N'OUTSIDE CRITERIA' END;
    DECLARE @decisionCode nvarchar(60) =
        CASE WHEN @processType = N'SUCCESSION' THEN N'NONHIPO' ELSE N'NOMINATED' END;

    CREATE TABLE #add (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY, OrgCode nvarchar(40) NOT NULL);
    INSERT #add (PersonnelNo, OrgCode)
    SELECT e.PersonnelNo, e.OrgCode
    FROM @People p
    JOIN sel.Employee e ON e.PersonnelNo = p.Id
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
    WHERE e.IsActive = 1;

    IF @processType = N'SUCCESSION'
        /* A Non HIPO pull comes from the cycle's own pool, not the whole roster. */
        DELETE a FROM #add a
        WHERE NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                          WHERE cc.CycleId = @cycleId AND cc.PersonnelNo = a.PersonnelNo);

    IF NOT EXISTS (SELECT 1 FROM #add)
    BEGIN
        SET @Problem = N'None of those people could be added: they are outside your organisations, or not in this cycle''s pool.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        DROP TABLE #add; RETURN;
    END;

    BEGIN TRAN;

    /* The snapshot is never recomputed, but people added by hand join it — that is a
       decision somebody took, not a re-resolution of the criteria. */
    INSERT sel.CycleCandidate (CycleId, PersonnelNo, SourceCode, OrgCode, AddedByLogin)
    SELECT @cycleId, a.PersonnelNo, @sourceCode, a.OrgCode, @LoginName
    FROM #add a
    WHERE NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                      WHERE cc.CycleId = @cycleId AND cc.PersonnelNo = a.PersonnelNo);

    INSERT sel.CandidateSource (CycleId, PersonnelNo, SourceCode, AddedByLogin)
    SELECT @cycleId, a.PersonnelNo, @sourceCode, @LoginName
    FROM #add a
    WHERE NOT EXISTS (SELECT 1 FROM sel.CandidateSource cs
                      WHERE cs.CycleId = @cycleId AND cs.PersonnelNo = a.PersonnelNo AND cs.SourceCode = @sourceCode);

    INSERT sel.ProcessCandidate (CycleProcessId, PersonnelNo, SourceCode, AddedByLogin)
    SELECT @processId, a.PersonnelNo, @sourceCode, @LoginName
    FROM #add a
    WHERE NOT EXISTS (SELECT 1 FROM sel.ProcessCandidate pc
                      WHERE pc.CycleProcessId = @processId AND pc.PersonnelNo = a.PersonnelNo);

    /* Adding somebody is itself a decision, and is logged as one. */
    INSERT sel.CandidateDecision (CycleId, CycleProcessId, CycleStageId, PersonnelNo,
                                  DecisionValueId, Reason, PerformerLevelValueId, ActorLogin, IsTest, OrgCode)
    SELECT @cycleId, @processId, @CycleStageId, a.PersonnelNo,
           cfg.fn_DomainValueId(N'DECISION', @decisionCode),
           N'Added from the roster in ' + (SELECT Name FROM sel.CycleStage WHERE CycleStageId = @CycleStageId),
           @performerId, @LoginName, @TestMode, a.OrgCode
    FROM #add a;

    DECLARE @n int = (SELECT COUNT(*) FROM #add);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @cycleId) + N'/' + CONVERT(nvarchar(10), @n) + N' people';
    EXEC audit.usp_Log @TableName = N'sel.CycleCandidate', @KeyText = @keyText, @ActionCode = N'ADD_PEOPLE',
                       @LoginName = @LoginName;

    SELECT a.PersonnelNo, e.FullName, e.OrgCode, e.JobTitle, SourceCode = @sourceCode
    FROM #add a JOIN sel.Employee e ON e.PersonnelNo = a.PersonnelNo;

    DROP TABLE #add;
END
GO
PRINT '  sel.usp_Candidate_AddPeople       applied';
GO

/* sel.usp_Candidate_Search — the search inside the + Add people modal. */
CREATE OR ALTER PROCEDURE sel.usp_Candidate_Search
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @Search       nvarchar(200) = NULL,
    @Top          int = 100
AS
BEGIN
    SET NOCOUNT ON;
    IF @Top IS NULL OR @Top < 1 SET @Top = 100;

    DECLARE @cycleId int, @processType nvarchar(30);
    SELECT @cycleId = p.CycleId, @processType = p.ProcessTypeCode
    FROM sel.CycleStage s JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    WHERE s.CycleStageId = @CycleStageId;

    SELECT TOP (@Top)
           e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle, e.GradeCode,
           SourceCode = CASE WHEN cc.PersonnelNo IS NOT NULL THEN cc.SourceCode
                             WHEN @processType = N'SUCCESSION' THEN N'ELIGIBLE'
                             ELSE N'OUTSIDE CRITERIA' END,
           AlreadyIn = CASE WHEN cc.PersonnelNo IS NOT NULL THEN 1 ELSE 0 END
    FROM sel.Employee e
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    LEFT JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = e.PersonnelNo
    WHERE e.IsActive = 1
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
           OR e.PersonnelNo LIKE N'%' + @Search + N'%'
           OR e.JobTitle LIKE N'%' + @Search + N'%'
           OR o.Name LIKE N'%' + @Search + N'%')
      /* In a succession stage only the cycle's own pool may be pulled from. */
      AND (@processType <> N'SUCCESSION' OR cc.PersonnelNo IS NOT NULL)
    ORDER BY e.FullName;
END
GO
PRINT '  sel.usp_Candidate_Search          applied';
GO


/* =====================================================================================
   11_stage.sql, continued  —  profile, compare, suggestions, succession, saved views
   ===================================================================================== */

PRINT '';
PRINT '== 11_stage (part 2) =================================================';
GO

/* sel.usp_Candidate_Profile — the facts, the tiles, the bars and the readiness ladder.
   The ladder is the reason this screen exists, so it reads the same procedure the
   attainment panel reads.                                                              */
CREATE OR ALTER PROCEDURE sel.usp_Candidate_Profile
    @LoginName   nvarchar(128),
    @PersonnelNo nvarchar(30),
    @CycleId     int = NULL,
    @AsOf        date = NULL,
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    /* Row-level security applies to a profile too. */
    IF NOT EXISTS (SELECT 1 FROM sel.Employee e
                   JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
                   WHERE e.PersonnelNo = @PersonnelNo)
    BEGIN
        SET @Problem = N'This person is not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        RETURN;
    END;

    /* 1 — the facts. */
    SELECT e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, o.OrgLevel,
           e.JobTitle, e.PermJobSuffix, e.PermJobSuffixDesc, e.CurrentJobSuffix,
           e.GradeCode, e.ManagementLevelCode, e.HireDate, e.PromotionDate,
           /* Age is derived against the as-of date, never against today. */
           AgeYears = CASE WHEN e.BirthDate IS NULL THEN NULL
                           ELSE DATEDIFF(YEAR, e.BirthDate, @AsOf)
                              - CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, e.BirthDate, @AsOf), e.BirthDate) > @AsOf
                                     THEN 1 ELSE 0 END END,
           TenureYears = (SELECT NumValue FROM sel.EmployeeMetric m
                          WHERE m.PersonnelNo = e.PersonnelNo AND m.MetricKey = N'TenureYears'),
           e.IsActive, e.PermChiefInd, e.Email
    FROM sel.Employee e
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    WHERE e.PersonnelNo = @PersonnelNo;

    /* 2 — the tiles. */
    SELECT m.MetricKey, d.Name, d.Description, m.NumValue, m.TextValue, m.AsOfDate, d.SortOrder
    FROM sel.EmployeeMetric m
    JOIN sel.MetricDefinition d ON d.MetricKey = m.MetricKey
    WHERE m.PersonnelNo = @PersonnelNo AND d.IsActive = 1
    ORDER BY d.SortOrder;

    /* 3 — performance, last years as letters, never averaged on load. */
    SELECT RatingYear, RatingCode, RatingValue,
           RatingRole = (SELECT TOP (1) dv.SemanticRole FROM cfg.fn_DomainValues(N'RATING_BAND') dv
                         WHERE dv.ValueCode = p.RatingCode)
    FROM sel.EmployeePmp p
    WHERE p.PersonnelNo = @PersonnelNo
    ORDER BY RatingYear DESC;

    /* 4 — assignments and coverage. */
    SELECT EmployeeCoverageId, ItemCode, CoverageType, Department, OrgCode, PositionSuffix,
           PositionCode, StartDate, EndDate, Days, Months
    FROM sel.EmployeeCoverage WHERE PersonnelNo = @PersonnelNo
    ORDER BY ISNULL(StartDate, '1900-01-01') DESC;

    /* 5 — course, assessment and survey completion. */
    SELECT r.EmployeeRecordId, r.KindCode, k.Name AS KindName, r.ItemCode,
           ItemName = ci.Name, r.Status, r.Score, r.MaxScore, r.CompletedOn, r.ExpiresOn, r.Source,
           /* An expired record is not a completion, and the screen must be able to say so. */
           IsExpired = CONVERT(bit, CASE WHEN r.ExpiresOn IS NOT NULL AND r.ExpiresOn < @AsOf THEN 1 ELSE 0 END)
    FROM sel.EmployeeRecord r
    JOIN sel.RequirementKind k ON k.KindCode = r.KindCode
    LEFT JOIN sel.CatalogItem ci ON ci.KindCode = r.KindCode AND ci.ItemCode = r.ItemCode
    WHERE r.PersonnelNo = @PersonnelNo
    ORDER BY k.SortOrder, r.ItemCode;

    /* 6 — the level history strip. */
    SELECT HistoryYear, LevelCode, CycleId,
           CycleName = (SELECT Name FROM sel.Cycle c WHERE c.CycleId = h.CycleId)
    FROM sel.ReadinessHistory h WHERE h.PersonnelNo = @PersonnelNo
    ORDER BY HistoryYear DESC;

    /* 7 — the decisions taken about this person. */
    SELECT TOP (50) d.DecisionId, d.CycleId, c.Name AS CycleName, s.Name AS StageName,
           dv.ValueCode AS DecisionCode, dv.Name AS DecisionName, dv.SemanticRole,
           d.Reason, d.ActorLogin, d.DecidedOnUtc, d.IsTest
    FROM sel.CandidateDecision d
    JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
    LEFT JOIN sel.Cycle c ON c.CycleId = d.CycleId
    LEFT JOIN sel.CycleStage s ON s.CycleStageId = d.CycleStageId
    WHERE d.PersonnelNo = @PersonnelNo
    ORDER BY d.DecidedOnUtc DESC;

    /* 8 — the readiness ladder, when we are looking at this person inside a cycle.
       Each level lists what it asks, what was met, and how far along they are. */
    IF @CycleId IS NOT NULL
        EXEC sel.usp_Attainment_PerPerson @LoginName = @LoginName, @CycleId = @CycleId,
             @PersonnelNo = @PersonnelNo, @AsOf = @AsOf;
END
GO
PRINT '  sel.usp_Candidate_Profile         applied';
GO

/* sel.usp_Candidate_Compare — up to six candidates side by side. */
CREATE OR ALTER PROCEDURE sel.usp_Candidate_Compare
    @LoginName nvarchar(128),
    @People    dbo.IdList READONLY,
    @CycleId   int = NULL,
    @AsOf      date = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @max int = CAST(ISNULL(cfg.fn_SettingNum(N'COMPARE_MAX'), 6) AS int);
    DECLARE @asked int = (SELECT COUNT(*) FROM @People);
    IF @asked > @max
    BEGIN
        SET @Problem = N'Up to ' + CONVERT(nvarchar(10), @max) + N' people can be compared at once, and you chose '
                     + CONVERT(nvarchar(10), @asked) + N'.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* The facts, side by side. */
    SELECT e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
           e.PermJobSuffix, e.GradeCode, e.ManagementLevelCode, e.HireDate, e.PromotionDate,
           PerformanceAvg3 = (SELECT NumValue FROM sel.EmployeeMetric m
                              WHERE m.PersonnelNo = e.PersonnelNo AND m.MetricKey = N'PerformanceAvg3'),
           DaysCovered     = (SELECT NumValue FROM sel.EmployeeMetric m
                              WHERE m.PersonnelNo = e.PersonnelNo AND m.MetricKey = N'DaysCovered'),
           CoursesCompleted= (SELECT NumValue FROM sel.EmployeeMetric m
                              WHERE m.PersonnelNo = e.PersonnelNo AND m.MetricKey = N'CoursesCompleted'),
           LatestDecision  = (SELECT TOP (1) dv.Name FROM sel.CandidateDecision d
                              JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
                              WHERE d.PersonnelNo = e.PersonnelNo AND (@CycleId IS NULL OR d.CycleId = @CycleId)
                              ORDER BY d.DecisionId DESC)
    FROM @People p
    JOIN sel.Employee e ON e.PersonnelNo = p.Id
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    ORDER BY e.FullName;

    /* The last three performance years for each, as letters. */
    SELECT pm.PersonnelNo, pm.RatingYear, pm.RatingCode, pm.RatingValue
    FROM @People p
    JOIN sel.EmployeePmp pm ON pm.PersonnelNo = p.Id
    JOIN sel.Employee e ON e.PersonnelNo = pm.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
    ORDER BY pm.PersonnelNo, pm.RatingYear DESC;
END
GO
PRINT '  sel.usp_Candidate_Compare         applied';
GO

/* sel.usp_Candidate_Suggestions — advisory ranking only.  It MUST NEVER write a decision,
   and the panel says so.                                                                */
CREATE OR ALTER PROCEDURE sel.usp_Candidate_Suggestions
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @Top          int = 25,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    IF @Top IS NULL OR @Top < 1 SET @Top = 25;

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    /* Signals: three-year performance, acting days, curriculum, grade, tenure.  Each one
       contributes a named part of the score so the panel can show WHY, not just a rank. */
    ;WITH sig AS
    (
        SELECT cc.PersonnelNo, e.FullName, e.OrgCode, e.GradeCode, e.JobTitle,
               Perf    = ISNULL((SELECT NumValue FROM sel.EmployeeMetric m
                                 WHERE m.PersonnelNo = cc.PersonnelNo AND m.MetricKey = N'PerformanceAvg3'), 0),
               Acting  = ISNULL((SELECT NumValue FROM sel.EmployeeMetric m
                                 WHERE m.PersonnelNo = cc.PersonnelNo AND m.MetricKey = N'DirectorActingDays'), 0),
               Courses = ISNULL((SELECT NumValue FROM sel.EmployeeMetric m
                                 WHERE m.PersonnelNo = cc.PersonnelNo AND m.MetricKey = N'CoursesCompleted'), 0),
               Tenure  = ISNULL((SELECT NumValue FROM sel.EmployeeMetric m
                                 WHERE m.PersonnelNo = cc.PersonnelNo AND m.MetricKey = N'TenureYears'), 0),
               Assessed = ISNULL((SELECT COUNT(*) FROM sel.EmployeeRecord r
                                  WHERE r.PersonnelNo = cc.PersonnelNo AND r.KindCode = N'ASSESSMENT'), 0)
        FROM sel.CycleCandidate cc
        JOIN sel.Employee e ON e.PersonnelNo = cc.PersonnelNo
        JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
        WHERE cc.CycleId = @cycleId
          /* Only people nobody has decided on yet: a suggestion about a settled case is noise. */
          AND NOT EXISTS (SELECT 1 FROM sel.CandidateDecision d
                          JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
                          WHERE d.CycleStageId = @CycleStageId AND d.PersonnelNo = cc.PersonnelNo
                            AND dv.ValueCode <> N'NONE')
    ),
    scored AS
    (
        SELECT *, Score = CAST(Perf * 20 + (Acting / 30.0) + Courses * 2 + Tenure + Assessed * 5 AS decimal(18,2))
        FROM sig
    )
    SELECT TOP (@Top)
           PersonnelNo, FullName, OrgCode, JobTitle, GradeCode,
           Perf, Acting, Courses, Tenure, Assessed, Score,
           /* The suggestion, and the words behind it. */
           SuggestedDecision = CASE WHEN Score >= 80 THEN N'NOMINATED'
                                    WHEN Score >= 40 THEN N'WATCH'
                                    ELSE N'DROPPED' END,
           Because = N'Three-year performance ' + CONVERT(nvarchar(20), CAST(Perf AS decimal(9,1)))
                   + N' · ' + CONVERT(nvarchar(20), CAST(Acting AS decimal(9,0))) + N' acting days'
                   + N' · ' + CONVERT(nvarchar(20), CAST(Courses AS decimal(9,0))) + N' courses'
                   + N' · ' + CONVERT(nvarchar(20), CAST(Tenure AS decimal(9,0))) + N' years'
                   + CASE WHEN Assessed = 0 THEN N' · not assessed' ELSE N'' END,
           /* The panel says, in words, that nothing here is recorded. */
           Advisory = cfg.fn_Message(N'SUGGESTIONS_ADVISORY')
    FROM scored
    ORDER BY Score DESC, FullName;
END
GO
PRINT '  sel.usp_Candidate_Suggestions     applied';
GO

/* sel.usp_Candidate_Trace — the auditor's answer to "why was this person pooled?" */
CREATE OR ALTER PROCEDURE sel.usp_Candidate_Trace
    @LoginName   nvarchar(128),
    @CycleId     int,
    @PersonnelNo nvarchar(30),
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                   JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
                   WHERE cc.CycleId = @CycleId AND cc.PersonnelNo = @PersonnelNo)
    BEGIN
        SET @Problem = N'This person is not in this cycle''s pool, or not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    SELECT t.CycleCandidateTraceId, t.CycleId, t.PersonnelNo, t.CriterionId, t.SetLabel,
           t.FieldName, t.OperatorName, t.TestedValue, t.ActualValue, t.Passed, t.CapturedOnUtc,
           FieldCaption = (SELECT TOP (1) f.Caption FROM sel.RosterField f WHERE f.FieldName = t.FieldName),
           Sentence = t.FieldName + N' ' + ISNULL(t.OperatorName, N'') + N' ' + ISNULL(t.TestedValue, N'')
    FROM sel.CycleCandidateTrace t
    WHERE t.CycleId = @CycleId AND t.PersonnelNo = @PersonnelNo
    ORDER BY t.SetLabel, t.CriterionId;

    SELECT cc.PersonnelNo, cc.SourceCode, cc.OrgCode, cc.AddedOnUtc, cc.AddedByLogin,
           e.FullName,
           SnapshotTakenOn = (SELECT PoolResolvedOnUtc FROM sel.Cycle WHERE CycleId = @CycleId)
    FROM sel.CycleCandidate cc
    JOIN sel.Employee e ON e.PersonnelNo = cc.PersonnelNo
    WHERE cc.CycleId = @CycleId AND cc.PersonnelNo = @PersonnelNo;
END
GO
PRINT '  sel.usp_Candidate_Trace           applied';
GO

/* =====================================================================================
   Succession
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_Succession_Plan_Save
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30),
    @Department   nvarchar(200),
    @LevelCode    nvarchar(20) = NULL,
    @PlanYear     smallint = NULL,
    @Remark       nvarchar(600) = NULL,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @processId int, @screenCode nvarchar(160), @performerId int;
    SELECT @cycleId = p.CycleId, @processId = s.CycleProcessId, @screenCode = sk.ScreenCode,
           @performerId = s.PerformerLevelValueId
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That stage no longer exists.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1 OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so the plan cannot be changed.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF NULLIF(LTRIM(RTRIM(@Department)), N'') IS NULL
    BEGIN
        SET @Problem = N'A plan needs a department, because that is what it plans against.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF @LevelCode IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sel.CycleReadiness
                                              WHERE CycleId = @cycleId AND LevelCode = @LevelCode)
    BEGIN
        SET @Problem = N'This cycle has no readiness level called ' + @LevelCode + N'.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                   JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
                   WHERE cc.CycleId = @cycleId AND cc.PersonnelNo = @PersonnelNo)
    BEGIN
        SET @Problem = N'This person is not in this cycle''s pool, or not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;

    IF @PlanYear IS NULL SET @PlanYear = YEAR(ISNULL((SELECT EndDate FROM sel.Cycle WHERE CycleId = @cycleId), @AsOf));
    DECLARE @orgCode nvarchar(40) = (SELECT OrgCode FROM sel.CycleCandidate
                                     WHERE CycleId = @cycleId AND PersonnelNo = @PersonnelNo);

    BEGIN TRAN;
    DECLARE @id bigint = (SELECT SuccessionPlanRowId FROM sel.SuccessionPlanRow
                          WHERE CycleId = @cycleId AND PersonnelNo = @PersonnelNo
                            AND Department = @Department AND PlanYear = @PlanYear);
    IF @id IS NULL
    BEGIN
        INSERT sel.SuccessionPlanRow (CycleId, CycleProcessId, PersonnelNo, Department, OrgCode,
                                      LevelCode, PlanYear, Remark, ActorLogin)
        VALUES (@cycleId, @processId, @PersonnelNo, @Department, @orgCode, @LevelCode, @PlanYear, @Remark, @LoginName);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE sel.SuccessionPlanRow
           SET LevelCode = ISNULL(@LevelCode, LevelCode), Remark = ISNULL(@Remark, Remark),
               IsDropped = 0, ActorLogin = @LoginName, DecidedOnUtc = SYSUTCDATETIME()
        WHERE SuccessionPlanRowId = @id;

    INSERT sel.CandidateDecision (CycleId, CycleProcessId, CycleStageId, PersonnelNo,
                                  DecisionValueId, Reason, PerformerLevelValueId, ActorLogin, IsTest, OrgCode)
    VALUES (@cycleId, @processId, @CycleStageId, @PersonnelNo,
            cfg.fn_DomainValueId(N'DECISION', N'DEVPLAN'),
            N'Planned in ' + @Department + ISNULL(N' at ' + @LevelCode, N''),
            @performerId, @LoginName, @TestMode, @orgCode);

    /* The level history strip is written as the plan is levelled. */
    IF @LevelCode IS NOT NULL
        MERGE sel.ReadinessHistory AS t
        USING (SELECT @PersonnelNo AS PersonnelNo, @PlanYear AS HistoryYear, @cycleId AS CycleId) AS s
           ON t.PersonnelNo = s.PersonnelNo AND t.HistoryYear = s.HistoryYear AND t.CycleId = s.CycleId
        WHEN MATCHED THEN UPDATE SET LevelCode = @LevelCode
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (PersonnelNo, HistoryYear, LevelCode, CycleId)
            VALUES (s.PersonnelNo, s.HistoryYear, @LevelCode, s.CycleId);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.SuccessionPlanRow', @KeyText = @keyText, @ActionCode = N'SAVE',
                       @LoginName = @LoginName;

    SELECT SuccessionPlanRowId = @id, PersonnelNo = @PersonnelNo, Department = @Department,
           LevelCode = @LevelCode, PlanYear = @PlanYear;
END
GO
PRINT '  sel.usp_Succession_Plan_Save      applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Succession_Plan_BulkAdd
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @People       dbo.IdList READONLY,
    @Department   nvarchar(200),
    @LevelCode    nvarchar(20) = NULL,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @person nvarchar(30), @n int = 0, @p nvarchar(400);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Id FROM @People;
    OPEN c; FETCH NEXT FROM c INTO @person;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sel.usp_Succession_Plan_Save @LoginName = @LoginName, @CycleStageId = @CycleStageId,
             @PersonnelNo = @person, @Department = @Department, @LevelCode = @LevelCode,
             @AsOf = @AsOf, @TestMode = @TestMode, @Problem = @p OUTPUT;
        IF @p IS NULL SET @n = @n + 1; ELSE SET @Problem = @p;
        FETCH NEXT FROM c INTO @person;
    END;
    CLOSE c; DEALLOCATE c;

    /* A partial success reports how many landed, rather than claiming all of them did. */
    IF @Problem IS NOT NULL AND @n > 0
        SET @Problem = CONVERT(nvarchar(10), @n) + N' of ' + CONVERT(nvarchar(10), (SELECT COUNT(*) FROM @People))
                     + N' were planned. ' + @Problem;

    SELECT Planned = @n, Department = @Department, LevelCode = @LevelCode;
END
GO
PRINT '  sel.usp_Succession_Plan_BulkAdd   applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Succession_Plan_Drop
    @LoginName           nvarchar(128),
    @SuccessionPlanRowId bigint,
    @Reason              nvarchar(600) = NULL,
    @Problem             nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT CycleId FROM sel.SuccessionPlanRow WHERE SuccessionPlanRowId = @SuccessionPlanRowId);
    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That plan row no longer exists.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF sel.fn_CycleStatusCode(@cycleId) = N'CLOSED'
    BEGIN
        SET @Problem = cfg.fn_Message(N'CLOSED_CYCLE');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;

    /* Dropping does not delete: the plan is history, and the log has to keep it. */
    UPDATE sel.SuccessionPlanRow
       SET IsDropped = 1, Remark = ISNULL(@Reason, Remark),
           ActorLogin = @LoginName, DecidedOnUtc = SYSUTCDATETIME()
    WHERE SuccessionPlanRowId = @SuccessionPlanRowId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @SuccessionPlanRowId);
    EXEC audit.usp_Log @TableName = N'sel.SuccessionPlanRow', @KeyText = @keyText, @ActionCode = N'DROP',
                       @AfterJson = @Reason, @LoginName = @LoginName;

    SELECT SuccessionPlanRowId = @SuccessionPlanRowId, Dropped = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Succession_Plan_Drop      applied';
GO

/* sel.usp_Succession_Plans — the plans in a cycle, with the level census. */
CREATE OR ALTER PROCEDURE sel.usp_Succession_Plans
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @Search       nvarchar(200) = NULL,
    @Department   nvarchar(200) = NULL,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    SELECT r.SuccessionPlanRowId, r.CycleId, r.PersonnelNo, r.Department, r.OrgCode,
           r.LevelCode, r.PlanYear, r.Remark, r.ActorLogin, r.DecidedOnUtc, r.IsDropped,
           e.FullName, e.JobTitle, e.GradeCode, o.Name AS OrgName,
           LevelName = (SELECT Name FROM sel.CycleReadiness lv
                        WHERE lv.CycleId = r.CycleId AND lv.LevelCode = r.LevelCode)
    FROM sel.SuccessionPlanRow r
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = r.OrgCode
    JOIN sel.Employee e ON e.PersonnelNo = r.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = r.OrgCode
    WHERE r.CycleId = @cycleId AND r.IsDropped = 0
      AND (@Department IS NULL OR r.Department = @Department)
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
           OR r.PersonnelNo LIKE N'%' + @Search + N'%' OR r.Department LIKE N'%' + @Search + N'%')
    ORDER BY r.Department, e.FullName;

    /* The level census. */
    SELECT lv.LevelCode, lv.Name, lv.ThresholdPct, lv.SortOrder,
           Planned = (SELECT COUNT(*) FROM sel.SuccessionPlanRow r
                      JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = r.OrgCode
                      WHERE r.CycleId = @cycleId AND r.IsDropped = 0 AND r.LevelCode = lv.LevelCode)
    FROM sel.CycleReadiness lv WHERE lv.CycleId = @cycleId ORDER BY lv.SortOrder;

    /* Departments already planned against, for the picker. */
    SELECT Department, Planned = COUNT(*)
    FROM sel.SuccessionPlanRow r
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = r.OrgCode
    WHERE r.CycleId = @cycleId AND r.IsDropped = 0
    GROUP BY Department ORDER BY Department;
END
GO
PRINT '  sel.usp_Succession_Plans          applied';
GO

/* sel.usp_Succession_ByPosition — positions with incumbents for the incumbent suffix,
   and the successors named against each.                                              */
CREATE OR ALTER PROCEDURE sel.usp_Succession_ByPosition
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @Search       nvarchar(200) = NULL,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);
    DECLARE @incumbentSuffix nvarchar(30) = (SELECT IncumbentSuffix FROM sel.Cycle WHERE CycleId = @cycleId);
    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'POSITION');

    IF @obj IS NULL
    BEGIN
        /* A missing source is never a silent zero. */
        SET @Problem = (SELECT BreaksWhenUnmapped FROM sel.TableMapping WHERE SourceKey = N'POSITION');
        SELECT TOP (0) CAST(NULL AS nvarchar(60)) AS PositionCode;
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionSlotId;
        RETURN;
    END;

    DECLARE @keyCol  nvarchar(128) = (SELECT KeyColumn  FROM sel.TableMapping WHERE SourceKey = N'POSITION');
    DECLARE @itemCol nvarchar(128) = (SELECT ItemColumn FROM sel.TableMapping WHERE SourceKey = N'POSITION');

    DECLARE @sql nvarchar(max) = N'
        SELECT PositionCode = CONVERT(nvarchar(60), ps.' + QUOTENAME(@itemCol) + N'),
               IncumbentPersonnelNo = CONVERT(nvarchar(30), ps.' + QUOTENAME(@keyCol) + N'),
               IncumbentName = e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
               e.PermJobSuffix,
               SuccessorCount = (SELECT COUNT(*) FROM sel.SuccessionSlot sl
                                 WHERE sl.CycleId = @cycleId
                                   AND sl.PositionCode = CONVERT(nvarchar(60), ps.' + QUOTENAME(@itemCol) + N'))
        FROM ' + @obj + N' ps
        JOIN sel.Employee e ON e.PersonnelNo = CONVERT(nvarchar(30), ps.' + QUOTENAME(@keyCol) + N')
        JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
        LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
        WHERE (@incumbentSuffix IS NULL OR e.PermJobSuffix = @incumbentSuffix)
          AND (@Search IS NULL OR e.FullName LIKE N''%'' + @Search + N''%''
               OR CONVERT(nvarchar(60), ps.' + QUOTENAME(@itemCol) + N') LIKE N''%'' + @Search + N''%'')
        ORDER BY 1;';

    BEGIN TRY
        EXEC sp_executesql @sql,
             N'@LoginName nvarchar(128), @cycleId int, @incumbentSuffix nvarchar(30), @Search nvarchar(200)',
             @LoginName = @LoginName, @cycleId = @cycleId,
             @incumbentSuffix = @incumbentSuffix, @Search = @Search;
    END TRY
    BEGIN CATCH
        SET @Problem = N'The positions could not be read: ' + ERROR_MESSAGE();
        SELECT TOP (0) CAST(NULL AS nvarchar(60)) AS PositionCode;
    END CATCH;

    /* The successors named against each position. */
    SELECT sl.SuccessionSlotId, sl.PositionCode, sl.IncumbentPersonnelNo, sl.SuccessorPersonnelNo,
           sl.LevelCode, sl.Remark, sl.ActorLogin, sl.DecidedOnUtc,
           SuccessorName = e.FullName, e.JobTitle, e.GradeCode,
           LevelName = (SELECT Name FROM sel.CycleReadiness lv
                        WHERE lv.CycleId = sl.CycleId AND lv.LevelCode = sl.LevelCode)
    FROM sel.SuccessionSlot sl
    JOIN sel.Employee e ON e.PersonnelNo = sl.SuccessorPersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
    WHERE sl.CycleId = @cycleId
    ORDER BY sl.PositionCode, e.FullName;
END
GO
PRINT '  sel.usp_Succession_ByPosition     applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Succession_Slot_Save
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PositionCode nvarchar(60),
    @SuccessorPersonnelNo nvarchar(30),
    @IncumbentPersonnelNo nvarchar(30) = NULL,
    @LevelCode    nvarchar(20) = NULL,
    @Remark       nvarchar(600) = NULL,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @processId int, @screenCode nvarchar(160), @performerId int;
    SELECT @cycleId = p.CycleId, @processId = s.CycleProcessId, @screenCode = sk.ScreenCode,
           @performerId = s.PerformerLevelValueId
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
       OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionSlotId; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so a successor cannot be named.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionSlotId; RETURN;
    END;

    DECLARE @orgCode nvarchar(40) = (SELECT OrgCode FROM sel.Employee WHERE PersonnelNo = @SuccessorPersonnelNo);
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@LoginName) sc WHERE sc.OrgCode = @orgCode)
    BEGIN
        SET @Problem = N'That person is not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionSlotId; RETURN;
    END;

    BEGIN TRAN;
    DECLARE @id bigint = (SELECT SuccessionSlotId FROM sel.SuccessionSlot
                          WHERE CycleId = @cycleId AND PositionCode = @PositionCode
                            AND SuccessorPersonnelNo = @SuccessorPersonnelNo);
    IF @id IS NULL
    BEGIN
        INSERT sel.SuccessionSlot (CycleId, PositionCode, IncumbentPersonnelNo, SuccessorPersonnelNo,
                                   LevelCode, Remark, OrgCode, ActorLogin)
        VALUES (@cycleId, @PositionCode, @IncumbentPersonnelNo, @SuccessorPersonnelNo,
                @LevelCode, @Remark, @orgCode, @LoginName);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE sel.SuccessionSlot SET LevelCode = ISNULL(@LevelCode, LevelCode),
               Remark = ISNULL(@Remark, Remark), ActorLogin = @LoginName, DecidedOnUtc = SYSUTCDATETIME()
        WHERE SuccessionSlotId = @id;

    INSERT sel.CandidateDecision (CycleId, CycleProcessId, CycleStageId, PersonnelNo,
                                  DecisionValueId, Reason, PerformerLevelValueId, ActorLogin, IsTest, OrgCode)
    VALUES (@cycleId, @processId, @CycleStageId, @SuccessorPersonnelNo,
            cfg.fn_DomainValueId(N'DECISION', N'SUCCESSOR'),
            N'Named against position ' + @PositionCode + ISNULL(N' at ' + @LevelCode, N''),
            @performerId, @LoginName, @TestMode, @orgCode);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.SuccessionSlot', @KeyText = @keyText, @ActionCode = N'SAVE',
                       @LoginName = @LoginName;

    SELECT SuccessionSlotId = @id, PositionCode = @PositionCode,
           SuccessorPersonnelNo = @SuccessorPersonnelNo, LevelCode = @LevelCode;
END
GO
PRINT '  sel.usp_Succession_Slot_Save      applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Succession_Slot_Remove
    @LoginName        nvarchar(128),
    @SuccessionSlotId bigint,
    @Problem          nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    DECLARE @cycleId int = (SELECT CycleId FROM sel.SuccessionSlot WHERE SuccessionSlotId = @SuccessionSlotId);
    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
    BEGIN
        SET @Problem = ISNULL(NULLIF(cfg.fn_Message(N'READONLY_REFUSAL'), N''), N'That successor is no longer named.');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionSlotId; RETURN;
    END;
    IF sel.fn_CycleStatusCode(@cycleId) = N'CLOSED'
    BEGIN
        SET @Problem = cfg.fn_Message(N'CLOSED_CYCLE');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionSlotId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT PositionCode, SuccessorPersonnelNo, LevelCode
                                     FROM sel.SuccessionSlot WHERE SuccessionSlotId = @SuccessionSlotId
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM sel.SuccessionSlot WHERE SuccessionSlotId = @SuccessionSlotId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @SuccessionSlotId);
    EXEC audit.usp_Log @TableName = N'sel.SuccessionSlot', @KeyText = @keyText, @ActionCode = N'REMOVE',
                       @BeforeJson = @before, @LoginName = @LoginName;
    SELECT SuccessionSlotId = @SuccessionSlotId, Removed = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Succession_Slot_Remove    applied';
GO

/* sel.usp_Succession_Readiness_Save — set the readiness level on a plan, with a remark. */
CREATE OR ALTER PROCEDURE sel.usp_Succession_Readiness_Save
    @LoginName           nvarchar(128),
    @CycleStageId        int,
    @SuccessionPlanRowId bigint,
    @LevelCode           nvarchar(20),
    @Remark              nvarchar(600) = NULL,
    @AsOf                date = NULL,
    @TestMode            bit = 0,
    @Problem             nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @person nvarchar(30), @org nvarchar(40), @dept nvarchar(200), @year smallint;
    SELECT @cycleId = CycleId, @person = PersonnelNo, @org = OrgCode, @dept = Department, @year = PlanYear
    FROM sel.SuccessionPlanRow WHERE SuccessionPlanRowId = @SuccessionPlanRowId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That plan row no longer exists.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so readiness cannot be set.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.CycleReadiness WHERE CycleId = @cycleId AND LevelCode = @LevelCode)
    BEGIN
        SET @Problem = N'This cycle has no readiness level called ' + ISNULL(@LevelCode, N'') + N'.';
        SELECT TOP (0) CAST(NULL AS bigint) AS SuccessionPlanRowId; RETURN;
    END;

    DECLARE @processId int = (SELECT CycleProcessId FROM sel.CycleStage WHERE CycleStageId = @CycleStageId);
    DECLARE @performerId int = (SELECT PerformerLevelValueId FROM sel.CycleStage WHERE CycleStageId = @CycleStageId);

    BEGIN TRAN;
    UPDATE sel.SuccessionPlanRow
       SET LevelCode = @LevelCode, Remark = ISNULL(@Remark, Remark),
           ActorLogin = @LoginName, DecidedOnUtc = SYSUTCDATETIME()
    WHERE SuccessionPlanRowId = @SuccessionPlanRowId;

    MERGE sel.ReadinessHistory AS t
    USING (SELECT @person AS PersonnelNo, @year AS HistoryYear, @cycleId AS CycleId) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.HistoryYear = s.HistoryYear AND t.CycleId = s.CycleId
    WHEN MATCHED THEN UPDATE SET LevelCode = @LevelCode
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, HistoryYear, LevelCode, CycleId)
        VALUES (s.PersonnelNo, s.HistoryYear, @LevelCode, s.CycleId);

    INSERT sel.CandidateDecision (CycleId, CycleProcessId, CycleStageId, PersonnelNo,
                                  DecisionValueId, Reason, PerformerLevelValueId, ActorLogin, IsTest, OrgCode)
    VALUES (@cycleId, @processId, @CycleStageId, @person,
            cfg.fn_DomainValueId(N'DECISION', N'READINESS'),
            N'Set to ' + @LevelCode + N' in ' + @dept + ISNULL(N' — ' + @Remark, N''),
            @performerId, @LoginName, @TestMode, @org);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @SuccessionPlanRowId);
    EXEC audit.usp_Log @TableName = N'sel.SuccessionPlanRow', @KeyText = @keyText, @ActionCode = N'READINESS',
                       @LoginName = @LoginName;

    SELECT SuccessionPlanRowId = @SuccessionPlanRowId, LevelCode = @LevelCode, PersonnelNo = @person;
END
GO
PRINT '  sel.usp_Succession_Readiness_Save applied';
GO

/* sel.usp_Succession_PlanCheck — the framework requirement met, against the plan-specific
   rule, showing where the days were ACTUALLY served.                                    */
CREATE OR ALTER PROCEDURE sel.usp_Succession_PlanCheck
    @LoginName           nvarchar(128),
    @SuccessionPlanRowId bigint,
    @AsOf                date = NULL,
    @Problem             nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @person nvarchar(30), @dept nvarchar(200), @level nvarchar(20), @org nvarchar(40);
    SELECT @cycleId = CycleId, @person = PersonnelNo, @dept = Department, @level = LevelCode, @org = OrgCode
    FROM sel.SuccessionPlanRow WHERE SuccessionPlanRowId = @SuccessionPlanRowId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That plan row no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@LoginName) sc WHERE sc.OrgCode = @org)
    BEGIN
        SET @Problem = N'This plan is not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* 1 — the plan and the whole-framework answer, from the same engine the ladder uses. */
    SELECT SuccessionPlanRowId = @SuccessionPlanRowId, PersonnelNo = @person,
           Department = @dept, LevelCode = @level,
           FullName = (SELECT FullName FROM sel.Employee WHERE PersonnelNo = @person);

    EXEC sel.usp_Attainment_PerPerson @LoginName = @LoginName, @CycleId = @cycleId,
         @PersonnelNo = @person, @AsOf = @AsOf;

    /* 2 — the plan-specific rule: days count only where the plan placed them.  This is
       where a framework requirement met "in general" and met "for this plan" diverge,
       and the screen has to show both. */
    SELECT Department = c.Department,
           DaysServed = SUM(ISNULL(c.Days, 0)),
           IsPlannedDepartment = CONVERT(bit, CASE WHEN c.Department = @dept THEN 1 ELSE 0 END),
           /* Spread across departments: how many distinct departments the days cover. */
           SpreadAcross = (SELECT COUNT(DISTINCT c2.Department) FROM sel.EmployeeCoverage c2
                           WHERE c2.PersonnelNo = @person)
    FROM sel.EmployeeCoverage c
    WHERE c.PersonnelNo = @person
    GROUP BY c.Department
    ORDER BY CASE WHEN c.Department = @dept THEN 0 ELSE 1 END, SUM(ISNULL(c.Days, 0)) DESC;

    /* 3 — the verdict in words. */
    DECLARE @inPlan decimal(18,4) = ISNULL((SELECT SUM(ISNULL(Days, 0)) FROM sel.EmployeeCoverage
                                            WHERE PersonnelNo = @person AND Department = @dept), 0);
    DECLARE @total decimal(18,4) = ISNULL((SELECT SUM(ISNULL(Days, 0)) FROM sel.EmployeeCoverage
                                           WHERE PersonnelNo = @person), 0);
    SELECT DaysInPlannedDepartment = @inPlan,
           DaysEverywhere = @total,
           Sentence = CASE
               WHEN @total = 0 THEN N'No coverage days are recorded for this person at all.'
               WHEN @inPlan = 0 THEN N'All ' + CONVERT(nvarchar(20), CAST(@total AS decimal(18,0)))
                                   + N' recorded days were served somewhere other than ' + @dept + N'.'
               WHEN @inPlan = @total THEN N'All ' + CONVERT(nvarchar(20), CAST(@total AS decimal(18,0)))
                                   + N' recorded days were served in ' + @dept + N'.'
               ELSE CONVERT(nvarchar(20), CAST(@inPlan AS decimal(18,0))) + N' of '
                  + CONVERT(nvarchar(20), CAST(@total AS decimal(18,0)))
                  + N' recorded days were served in ' + @dept + N'.' END;
END
GO
PRINT '  sel.usp_Succession_PlanCheck      applied';
GO

/* =====================================================================================
   The column catalogue and saved views
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_Column_Catalog
    @LoginName  nvarchar(128),
    @ScreenCode nvarchar(160) = NULL,
    @Search     nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ColumnCatalogId, ColumnName, Caption, GroupName, DataType,
           IsSensitive, IsDefault, SortOrder, IsPresent
    FROM sel.ColumnCatalog
    WHERE IsPresent = 1
      AND (@Search IS NULL OR ColumnName LIKE N'%' + @Search + N'%' OR Caption LIKE N'%' + @Search + N'%')
    ORDER BY GroupName, SortOrder, Caption;

    /* This viewer's saved views for the screen, plus the administrator's preset. */
    SELECT SavedViewId, LoginName, ScreenCode, ViewName, ColumnList, SortBy, SortDir, IsPreset, SavedOnUtc
    FROM sel.SavedView
    WHERE (@ScreenCode IS NULL OR ScreenCode = @ScreenCode)
      AND (LoginName = @LoginName OR IsPreset = 1)
    ORDER BY IsPreset DESC, ViewName;
END
GO
PRINT '  sel.usp_Column_Catalog            applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_SavedView_Save
    @LoginName  nvarchar(128),
    @ScreenCode nvarchar(160),
    @ViewName   nvarchar(120) = N'Default',
    @ColumnList nvarchar(max),
    @SortBy     nvarchar(128) = NULL,
    @SortDir    nvarchar(4) = NULL,
    @AsPreset   bit = 0,
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    /* Only an administrator may make a view the shared preset. */
    IF @AsPreset = 1 AND NOT EXISTS (SELECT 1 FROM sec.AppUser u
                                     JOIN sec.UserRole ur ON ur.AppUserId = u.AppUserId
                                     JOIN sec.Role r ON r.RoleId = ur.RoleId
                                     WHERE u.LoginName = @LoginName AND r.RoleCode = N'ADMIN')
    BEGIN
        SET @Problem = N'Only an administrator can make a column set the preset for everybody.';
        SELECT TOP (0) CAST(NULL AS int) AS SavedViewId; RETURN;
    END;

    /* Every column must be one the catalogue knows. */
    DECLARE @bad nvarchar(128);
    SELECT TOP (1) @bad = LTRIM(RTRIM(s.value))
    FROM STRING_SPLIT(@ColumnList, N',') s
    LEFT JOIN sel.ColumnCatalog cc ON cc.ColumnName = LTRIM(RTRIM(s.value))
    WHERE LTRIM(RTRIM(s.value)) <> N'' AND cc.ColumnName IS NULL;

    IF @bad IS NOT NULL
    BEGIN
        SET @Problem = N'"' + @bad + N'" is not a column of the employee record.';
        SELECT TOP (0) CAST(NULL AS int) AS SavedViewId; RETURN;
    END;

    DECLARE @owner nvarchar(128) = CASE WHEN @AsPreset = 1 THEN NULL ELSE @LoginName END;
    DECLARE @id int = (SELECT SavedViewId FROM sel.SavedView
                       WHERE ScreenCode = @ScreenCode
                         AND ((@AsPreset = 1 AND IsPreset = 1 AND LoginName IS NULL)
                           OR (@AsPreset = 0 AND LoginName = @LoginName AND ViewName = @ViewName)));

    IF @id IS NULL
    BEGIN
        INSERT sel.SavedView (LoginName, ScreenCode, ViewName, ColumnList, SortBy, SortDir, IsPreset)
        VALUES (@owner, @ScreenCode, @ViewName, @ColumnList, @SortBy, @SortDir, @AsPreset);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE sel.SavedView SET ColumnList = @ColumnList, SortBy = @SortBy, SortDir = @SortDir,
               SavedOnUtc = SYSUTCDATETIME() WHERE SavedViewId = @id;

    DECLARE @keyText nvarchar(200) = @ScreenCode + N'/' + @ViewName;
    DECLARE @act nvarchar(20) = CASE WHEN @AsPreset = 1 THEN N'PRESET' ELSE N'SAVE' END;
    EXEC audit.usp_Log @TableName = N'sel.SavedView', @KeyText = @keyText, @ActionCode = @act,
                       @LoginName = @LoginName;

    SELECT SavedViewId = @id, ScreenCode = @ScreenCode, ViewName = @ViewName,
           ColumnList = @ColumnList, IsPreset = @AsPreset;
END
GO
PRINT '  sel.usp_SavedView_Save            applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_SavedView_Reset
    @LoginName  nvarchar(128),
    @ScreenCode nvarchar(160),
    @ViewName   nvarchar(120) = N'Default',
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    DELETE FROM sel.SavedView
    WHERE LoginName = @LoginName AND ScreenCode = @ScreenCode AND ViewName = @ViewName;

    /* Reset falls back to the preset, or to the catalogue's own defaults. */
    SELECT ColumnList = ISNULL(
        (SELECT TOP (1) ColumnList FROM sel.SavedView
         WHERE ScreenCode = @ScreenCode AND IsPreset = 1 AND LoginName IS NULL),
        STUFF((SELECT N',' + ColumnName FROM sel.ColumnCatalog
               WHERE IsDefault = 1 AND IsPresent = 1 ORDER BY SortOrder
               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, N''));
END
GO
PRINT '  sel.usp_SavedView_Reset           applied';
GO

/* =====================================================================================
   Who can perform a stage
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_StagePerformer_List
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT sp.StagePerformerId, sp.LevelValueId, dv.ValueCode AS LevelCode, dv.Name AS LevelName,
           sp.IsActive, sp.SortOrder,
           /* How many stages use each title, so removing one shows what it costs. */
           UsageCount = (SELECT COUNT(*) FROM sel.CycleStage s WHERE s.PerformerLevelValueId = sp.LevelValueId)
    FROM sel.StagePerformer sp
    JOIN cfg.DomainValue dv ON dv.DomainValueId = sp.LevelValueId
    ORDER BY sp.SortOrder, dv.SortOrder;

    /* Titles that could be added. */
    SELECT dv.DomainValueId AS LevelValueId, dv.ValueCode AS LevelCode, dv.Name AS LevelName, dv.SortOrder
    FROM cfg.fn_DomainValues(N'MANAGEMENT_LEVEL') dv
    WHERE NOT EXISTS (SELECT 1 FROM sel.StagePerformer sp WHERE sp.LevelValueId = dv.DomainValueId)
    ORDER BY dv.SortOrder;
END
GO
PRINT '  sel.usp_StagePerformer_List       applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_StagePerformer_Add
    @LoginName nvarchar(128),
    @LevelCode nvarchar(60),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS StagePerformerId; RETURN;
    END;

    DECLARE @valueId int = cfg.fn_DomainValueId(N'MANAGEMENT_LEVEL', @LevelCode);
    IF @valueId IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@LevelCode, N'') + N'" is not one of the management levels.';
        SELECT TOP (0) CAST(NULL AS int) AS StagePerformerId; RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM sel.StagePerformer WHERE LevelValueId = @valueId)
        INSERT sel.StagePerformer (LevelValueId, SortOrder)
        VALUES (@valueId, ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.StagePerformer), 10));
    ELSE
        UPDATE sel.StagePerformer SET IsActive = 1 WHERE LevelValueId = @valueId;

    EXEC audit.usp_Log @TableName = N'sel.StagePerformer', @KeyText = @LevelCode, @ActionCode = N'ADD',
                       @LoginName = @LoginName;
    SELECT StagePerformerId = (SELECT StagePerformerId FROM sel.StagePerformer WHERE LevelValueId = @valueId),
           LevelCode = @LevelCode;
END
GO
PRINT '  sel.usp_StagePerformer_Add        applied';
GO

/* Removing a title clears it from every design, and says how many that was. */
CREATE OR ALTER PROCEDURE sel.usp_StagePerformer_Remove
    @LoginName nvarchar(128),
    @LevelCode nvarchar(60),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS StagePerformerId; RETURN;
    END;

    DECLARE @valueId int = cfg.fn_DomainValueId(N'MANAGEMENT_LEVEL', @LevelCode);
    DECLARE @used int = (SELECT COUNT(*) FROM sel.CycleStage WHERE PerformerLevelValueId = @valueId);

    BEGIN TRAN;
    UPDATE sel.CycleStage SET PerformerLevelValueId = NULL WHERE PerformerLevelValueId = @valueId;
    UPDATE sel.StagePerformer SET IsActive = 0 WHERE LevelValueId = @valueId;
    COMMIT;

    EXEC audit.usp_Log @TableName = N'sel.StagePerformer', @KeyText = @LevelCode, @ActionCode = N'REMOVE',
                       @LoginName = @LoginName;

    SELECT LevelCode = @LevelCode, ClearedFromStages = @used,
           Note = CASE WHEN @used = 0 THEN NULL
                       ELSE N'It was cleared from ' + CONVERT(nvarchar(10), @used) + N' stage'
                          + CASE WHEN @used = 1 THEN N'' ELSE N's' END
                          + N', which now need a performer set again.' END;
END
GO
PRINT '  sel.usp_StagePerformer_Remove     applied';
GO

/* sel.usp_CandidateFlag_Rebuild — the also-in-other-cycles cache, rebuilt on open. */
CREATE OR ALTER PROCEDURE sel.usp_CandidateFlag_Rebuild
    @LoginName nvarchar(128) = NULL,
    @CycleId   int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
    IF @CycleId IS NULL DELETE FROM sel.CandidateFlag;
    ELSE                DELETE FROM sel.CandidateFlag WHERE CycleId = @CycleId;

    INSERT sel.CandidateFlag (PersonnelNo, CycleId, OtherCycleId)
    SELECT a.PersonnelNo, a.CycleId, b.CycleId
    FROM sel.CycleCandidate a
    JOIN sel.CycleCandidate b ON b.PersonnelNo = a.PersonnelNo AND b.CycleId <> a.CycleId
    JOIN sel.Cycle cb ON cb.CycleId = b.CycleId
    JOIN cfg.DomainValue dv ON dv.DomainValueId = cb.StatusValueId AND dv.ValueCode = N'ACTIVE'
    WHERE (@CycleId IS NULL OR a.CycleId = @CycleId);
    COMMIT;

    SELECT Flags = (SELECT COUNT(*) FROM sel.CandidateFlag WHERE (@CycleId IS NULL OR CycleId = @CycleId));
END
GO
PRINT '  sel.usp_CandidateFlag_Rebuild     applied';
GO

/* =====================================================================================
   Seeds for this file's own reference tables
   ===================================================================================== */

/* The management levels a stage may be performed by. */
MERGE sel.StagePerformer AS t
USING (SELECT dv.DomainValueId, dv.SortOrder FROM cfg.fn_DomainValues(N'MANAGEMENT_LEVEL') dv) AS s
   ON t.LevelValueId = s.DomainValueId
WHEN NOT MATCHED BY TARGET THEN
    INSERT (LevelValueId, SortOrder) VALUES (s.DomainValueId, s.SortOrder);
PRINT '  sel.StagePerformer                seeded';
GO

/* The funnel pills.  Group 1 is where people arrive, group 2 is where decisions put them,
   and the outcome pill is the sum of what the next stage inherits.                      */
MERGE sel.FunnelPill AS t
USING (VALUES
 /* Identify: Eligible · Existing Pool | New Nominations · Watch list · Dropped | Total */
 (N'TR_IDENTIFY', N'ELIGIBLE',        N'Eligible',            N'Meets the criteria, was not carried in, and has no decision yet.', 1, N'neutral',  0, 0, 10),
 (N'TR_IDENTIFY', N'EXISTING_POOL',   N'Existing Pool',       N'Carried in from last year''s pool, with no decision yet.',          1, N'info',     0, 0, 20),
 (N'TR_IDENTIFY', N'NEW_NOMINATIONS', N'New Nominations',     N'Nominated in this stage.',                                         2, N'positive', 0, 1, 30),
 (N'TR_IDENTIFY', N'WATCH',           N'Watch list',          N'Set aside to look at again, not nominated.',                       2, N'warning',  0, 0, 40),
 (N'TR_IDENTIFY', N'DROPPED',         N'Dropped',             N'Taken out of this cycle, with a reason.',                          2, N'danger',   0, 0, 50),
 (N'TR_IDENTIFY', N'TOTAL',           N'Total Nominations',   N'What the next stage inherits: the existing pool still in, plus the new nominations.', 3, N'outcome', 1, 0, 60),

 /* Review: everyone is nominated until changed. */
 (N'TR_REVIEW', N'NEW_NOMINATIONS', N'New Nominations',   N'Nominated, and not changed in this stage.',                   1, N'positive', 0, 1, 10),
 (N'TR_REVIEW', N'EXISTING_POOL',   N'Existing Pool',     N'Carried in, with no review decision yet.',                    1, N'info',     0, 1, 20),
 (N'TR_REVIEW', N'WATCH',           N'Watch list',        N'Moved to the watch list in review, with a reason.',           2, N'warning',  0, 0, 30),
 (N'TR_REVIEW', N'DROPPED',         N'Dropped',           N'Dropped in review, with a reason.',                           2, N'danger',   0, 0, 40),
 (N'TR_REVIEW', N'TOTAL',           N'Total Nominations', N'What calibration inherits.',                                  3, N'outcome',  1, 0, 50),

 /* Calibration: the four grades are the outcome. */
 (N'TR_CALIBRATE', N'NEW_NOMINATIONS', N'New Nominations',       N'Nominated, and not yet calibrated.',                 1, N'neutral',  0, 0, 10),
 (N'TR_CALIBRATE', N'EXISTING_POOL',   N'Existing Pool',         N'Carried in, and not yet calibrated.',                1, N'info',     0, 0, 20),
 (N'TR_CALIBRATE', N'VP_VERY_STRONG',  N'VP-Very Strong',        N'Calibrated at vice-president level as very strong.', 2, N'positive', 0, 1, 30),
 (N'TR_CALIBRATE', N'DIR_VERY_STRONG', N'Director-Very Strong',  N'Calibrated at director level as very strong.',       2, N'positive', 0, 1, 40),
 (N'TR_CALIBRATE', N'DIR_STRONG',      N'Director-Strong',       N'Calibrated at director level as strong.',            2, N'positive', 0, 1, 50),
 (N'TR_CALIBRATE', N'MGR_STRONG',      N'Manager-Strong',        N'Calibrated at manager level as strong.',             2, N'positive', 0, 1, 60),
 (N'TR_CALIBRATE', N'WATCH',           N'Watch list',            N'Moved to the watch list in calibration.',            2, N'warning',  0, 0, 70),
 (N'TR_CALIBRATE', N'DROPPED',         N'Dropped',               N'Dropped in calibration, with a reason.',             2, N'danger',   0, 0, 80),
 (N'TR_CALIBRATE', N'TOTAL',           N'Total Nominations',     N'What the high-potential pool inherits.',             3, N'outcome',  1, 0, 90),

 /* Succession and development reuse the same shape. */
 (N'SU_IDENTIFY', N'ELIGIBLE',        N'HIPO pool',        N'Survivors of calibration, with no plan yet.',  1, N'neutral',  0, 0, 10),
 (N'SU_IDENTIFY', N'EXISTING_POOL',   N'Existing Pool',    N'Carried in from last year''s pool.',           1, N'info',     0, 0, 20),
 (N'SU_IDENTIFY', N'NEW_NOMINATIONS', N'Planned',          N'Planned against at least one department.',     2, N'positive', 0, 1, 30),
 (N'SU_IDENTIFY', N'WATCH',           N'Watch list',       N'Set aside for now.',                           2, N'warning',  0, 0, 40),
 (N'SU_IDENTIFY', N'DROPPED',         N'Dropped',          N'Taken out of the plan, with a reason.',        2, N'danger',   0, 0, 50),
 (N'SU_IDENTIFY', N'TOTAL',           N'Total Planned',    N'What succession review inherits.',             3, N'outcome',  1, 0, 60),

 (N'SU_REVIEW', N'NEW_NOMINATIONS', N'Planned',        N'Planned, and not changed in this stage.',  1, N'positive', 0, 1, 10),
 (N'SU_REVIEW', N'EXISTING_POOL',   N'Existing Pool',  N'Carried in, with no review decision yet.', 1, N'info',     0, 1, 20),
 (N'SU_REVIEW', N'WATCH',           N'Watch list',     N'Moved to the watch list in review.',       2, N'warning',  0, 0, 30),
 (N'SU_REVIEW', N'DROPPED',         N'Dropped',        N'Dropped in review, with a reason.',        2, N'danger',   0, 0, 40),
 (N'SU_REVIEW', N'TOTAL',           N'Total Planned',  N'What the plan carries forward.',           3, N'outcome',  1, 0, 50),

 (N'SU_CALIBRATE', N'NEW_NOMINATIONS', N'Planned',       N'Planned, and not yet calibrated.',        1, N'neutral',  0, 0, 10),
 (N'SU_CALIBRATE', N'EXISTING_POOL',   N'Existing Pool', N'Carried in, and not yet calibrated.',     1, N'info',     0, 0, 20),
 (N'SU_CALIBRATE', N'VP_VERY_STRONG',  N'VP-Very Strong',       N'Calibrated as very strong at vice-president level.', 2, N'positive', 0, 1, 30),
 (N'SU_CALIBRATE', N'DIR_VERY_STRONG', N'Director-Very Strong', N'Calibrated as very strong at director level.',       2, N'positive', 0, 1, 40),
 (N'SU_CALIBRATE', N'DIR_STRONG',      N'Director-Strong',      N'Calibrated as strong at director level.',            2, N'positive', 0, 1, 50),
 (N'SU_CALIBRATE', N'MGR_STRONG',      N'Manager-Strong',       N'Calibrated as strong at manager level.',             2, N'positive', 0, 1, 60),
 (N'SU_CALIBRATE', N'WATCH',           N'Watch list',    N'Moved to the watch list in calibration.', 2, N'warning',  0, 0, 70),
 (N'SU_CALIBRATE', N'DROPPED',         N'Dropped',       N'Dropped in calibration, with a reason.',  2, N'danger',   0, 0, 80),
 (N'SU_CALIBRATE', N'TOTAL',           N'Total Planned', N'What the plan carries forward.',          3, N'outcome',  1, 0, 90),

 (N'DV_IDENTIFY', N'ELIGIBLE',        N'No activity yet',  N'In the cohort, with nothing proposed yet.',  1, N'neutral',  0, 0, 10),
 (N'DV_IDENTIFY', N'EXISTING_POOL',   N'Existing Pool',    N'Carried in from last year''s pool.',         1, N'info',     0, 0, 20),
 (N'DV_IDENTIFY', N'NEW_NOMINATIONS', N'Activity proposed',N'An activity or curriculum has been proposed.',2, N'positive', 0, 1, 30),
 (N'DV_IDENTIFY', N'WATCH',           N'Watch list',       N'Set aside for now.',                         2, N'warning',  0, 0, 40),
 (N'DV_IDENTIFY', N'DROPPED',         N'Not required',     N'Marked as not needing an activity.',         2, N'muted',    0, 0, 50),
 (N'DV_IDENTIFY', N'TOTAL',           N'Total proposed',   N'What development review inherits.',          3, N'outcome',  1, 0, 60),

 (N'DV_REVIEW', N'NEW_NOMINATIONS', N'Proposed',      N'Proposed, and not changed in this stage.', 1, N'positive', 0, 1, 10),
 (N'DV_REVIEW', N'EXISTING_POOL',   N'Existing Pool', N'Carried in, with no review decision yet.', 1, N'info',     0, 1, 20),
 (N'DV_REVIEW', N'WATCH',           N'Returned',      N'Returned to identify for another look.',   2, N'warning',  0, 0, 30),
 (N'DV_REVIEW', N'DROPPED',         N'Not required',  N'Marked as not needing an activity.',       2, N'muted',    0, 0, 40),
 (N'DV_REVIEW', N'TOTAL',           N'Approved into the plan', N'What the individual development plan inherits.', 3, N'outcome', 1, 0, 50)
) AS s (StageKindCode, PillCode, Caption, Tooltip, GroupNo, SemanticRole, IsOutcome, CountsToTotal, SortOrder)
   ON t.StageKindCode = s.StageKindCode AND t.PillCode = s.PillCode
WHEN MATCHED THEN UPDATE SET Caption = s.Caption, Tooltip = s.Tooltip, GroupNo = s.GroupNo,
                             SemanticRole = s.SemanticRole, IsOutcome = s.IsOutcome,
                             CountsToTotal = s.CountsToTotal, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StageKindCode, PillCode, Caption, Tooltip, GroupNo, SemanticRole, IsOutcome, CountsToTotal, SortOrder)
    VALUES (s.StageKindCode, s.PillCode, s.Caption, s.Tooltip, s.GroupNo, s.SemanticRole,
            s.IsOutcome, s.CountsToTotal, s.SortOrder);
PRINT '  sel.FunnelPill                    seeded';
GO

PRINT '== 11_stage complete =================================================';
GO
