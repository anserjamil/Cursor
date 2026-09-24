/* =====================================================================================
   05_cycle.sql  —  the cycle, its design, its processes and stages, and its decisions
   -------------------------------------------------------------------------------------
   One design model runs three kinds of cycle: Talent review, Succession and Development.
   A cycle owns criteria (which resolve a pool), frameworks (which say what is asked),
   readiness levels (which say how much is enough), and processes with dated stages
   (which say who decides what, and when).

   sel.CycleCandidate is the pool *snapshot*: written once by sel.usp_Cycle_Open and never
   recomputed, so a review taken in March still shows March's figures.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 05_cycle ==========================================================';
GO

/* --- sel.ReadinessLevel ---------------------------------------------------------
   The preset ladder a new design starts from.  Per-cycle levels live in
   sel.CycleReadiness, because renaming R3 in one cycle must not touch another.       */
IF OBJECT_ID('sel.ReadinessLevel') IS NULL
BEGIN
    CREATE TABLE sel.ReadinessLevel
    (
        ReadinessLevelId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_ReadinessLevel PRIMARY KEY,
        LevelCode    nvarchar(20)  NOT NULL CONSTRAINT UQ_sel_ReadinessLevel_Code UNIQUE,
        Name         nvarchar(120) NOT NULL,
        Description  nvarchar(400) NULL,
        ThresholdPct decimal(9,4)  NULL,
        SortOrder    int           NOT NULL CONSTRAINT DF_sel_ReadinessLevel_Sort DEFAULT (0),
        IsActive     bit           NOT NULL CONSTRAINT DF_sel_ReadinessLevel_Act  DEFAULT (1)
    );
    PRINT '  sel.ReadinessLevel                created';
END
ELSE PRINT '  sel.ReadinessLevel                skipped';
GO

/* --- sel.Cycle ------------------------------------------------------------------ */
IF OBJECT_ID('sel.Cycle') IS NULL
BEGIN
    CREATE TABLE sel.Cycle
    (
        CycleId        int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_Cycle PRIMARY KEY,
        CycleCode      nvarchar(40)  NOT NULL CONSTRAINT UQ_sel_Cycle_Code UNIQUE,
        Name           nvarchar(300) NOT NULL,
        StartDate      date          NULL,
        EndDate        date          NULL,
        StatusValueId  int           NOT NULL CONSTRAINT FK_sel_Cycle_Status REFERENCES cfg.DomainValue(DomainValueId),
        OwnerLogin     nvarchar(128) NOT NULL,
        DelegateLogin  nvarchar(128) NULL,
        Notes          nvarchar(max) NULL,
        /* Talent Cycle only: the incumbent and successor job suffixes it covers. */
        IncumbentSuffix nvarchar(30) NULL,
        SuccessorSuffix nvarchar(30) NULL,
        /* The existing pool carried in: matched on end year - 1 and the successor suffix. */
        ExistingPoolCode nvarchar(60) NULL,
        ActiveMembersOnly bit         NOT NULL CONSTRAINT DF_sel_Cycle_ActiveOnly DEFAULT (1),
        RecipeId       int           NULL,
        CreatedByLogin nvarchar(128) NOT NULL,
        CreatedOnUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_Cycle_On DEFAULT (SYSUTCDATETIME()),
        OpenedOnUtc    datetime2(3)  NULL,
        ClosedOnUtc    datetime2(3)  NULL,
        /* Set once by sel.usp_Cycle_Open.  The snapshot is never recomputed. */
        PoolResolvedOnUtc datetime2(3) NULL,
        PoolCount      int           NULL
    );
    CREATE INDEX IX_sel_Cycle_Status ON sel.Cycle (StatusValueId) INCLUDE (CycleCode, Name, StartDate, EndDate);
    PRINT '  sel.Cycle                         created';
END
ELSE PRINT '  sel.Cycle                         skipped';
GO

IF OBJECT_ID('sel.CycleJobSuffix') IS NULL
BEGIN
    CREATE TABLE sel.CycleJobSuffix
    (
        CycleJobSuffixId int         IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleJobSuffix PRIMARY KEY,
        CycleId      int          NOT NULL CONSTRAINT FK_sel_CJS_Cycle REFERENCES sel.Cycle(CycleId),
        RoleCode     nvarchar(20) NOT NULL,     -- INCUMBENT | SUCCESSOR
        JobSuffix    nvarchar(30) NOT NULL,
        SuffixDesc   nvarchar(200) NULL,
        CONSTRAINT UQ_sel_CycleJobSuffix UNIQUE (CycleId, RoleCode, JobSuffix)
    );
    PRINT '  sel.CycleJobSuffix                created';
END
ELSE PRINT '  sel.CycleJobSuffix                skipped';
GO

/* --- criteria -------------------------------------------------------------------
   A criterion = field + operator + value(s).  Criteria live in sets (A, B, C...):
   inside a set conditions combine by all / any / none, and a set joins the previous
   ones by or also (union) / and also (intersection) / but not (difference).           */
IF OBJECT_ID('sel.CycleCriterionSet') IS NULL
BEGIN
    CREATE TABLE sel.CycleCriterionSet
    (
        CriterionSetId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleCriterionSet PRIMARY KEY,
        CycleId        int          NOT NULL CONSTRAINT FK_sel_CCS_Cycle REFERENCES sel.Cycle(CycleId),
        SetLabel       nvarchar(10) NOT NULL,
        SetModeValueId int          NOT NULL CONSTRAINT FK_sel_CCS_Mode REFERENCES cfg.DomainValue(DomainValueId),
        SetJoinValueId int          NULL     CONSTRAINT FK_sel_CCS_Join REFERENCES cfg.DomainValue(DomainValueId),
        SortOrder      int          NOT NULL CONSTRAINT DF_sel_CCS_Sort DEFAULT (0),
        CONSTRAINT UQ_sel_CCS UNIQUE (CycleId, SetLabel)
    );
    PRINT '  sel.CycleCriterionSet             created';
END
ELSE PRINT '  sel.CycleCriterionSet             skipped';
GO

IF OBJECT_ID('sel.CycleCriterion') IS NULL
BEGIN
    CREATE TABLE sel.CycleCriterion
    (
        CriterionId    int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleCriterion PRIMARY KEY,
        CriterionSetId int           NOT NULL CONSTRAINT FK_sel_CC_Set REFERENCES sel.CycleCriterionSet(CriterionSetId),
        RosterFieldId  int           NOT NULL CONSTRAINT FK_sel_CC_Field REFERENCES sel.RosterField(RosterFieldId),
        OperatorCode   nvarchar(30)  NOT NULL CONSTRAINT FK_sel_CC_Op REFERENCES cfg.Operator(OperatorCode),
        Value1         nvarchar(400) NULL,
        Value2         nvarchar(400) NULL,
        SortOrder      int           NOT NULL CONSTRAINT DF_sel_CC_Sort DEFAULT (0)
    );
    CREATE INDEX IX_sel_CC_Set ON sel.CycleCriterion (CriterionSetId, SortOrder);
    PRINT '  sel.CycleCriterion                created';
END
ELSE PRINT '  sel.CycleCriterion                skipped';
GO

/* --- what the cycle asks for ---------------------------------------------------- */
IF OBJECT_ID('sel.CycleFramework') IS NULL
BEGIN
    CREATE TABLE sel.CycleFramework
    (
        CycleFrameworkId int        IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleFramework PRIMARY KEY,
        CycleId        int          NOT NULL CONSTRAINT FK_sel_CF_Cycle     REFERENCES sel.Cycle(CycleId),
        DevFrameworkId int          NOT NULL CONSTRAINT FK_sel_CF_Framework REFERENCES sel.DevFramework(DevFrameworkId),
        AssignedOnUtc  datetime2(3) NOT NULL CONSTRAINT DF_sel_CF_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_CycleFramework UNIQUE (CycleId, DevFrameworkId)
    );
    PRINT '  sel.CycleFramework                created';
END
ELSE PRINT '  sel.CycleFramework                skipped';
GO

IF OBJECT_ID('sel.CycleReadiness') IS NULL
BEGIN
    CREATE TABLE sel.CycleReadiness
    (
        CycleReadinessId int         IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleReadiness PRIMARY KEY,
        CycleId      int           NOT NULL CONSTRAINT FK_sel_CR_Cycle REFERENCES sel.Cycle(CycleId),
        LevelCode    nvarchar(20)  NOT NULL,
        Name         nvarchar(120) NOT NULL,
        ThresholdPct decimal(9,4)  NULL,
        SortOrder    int           NOT NULL CONSTRAINT DF_sel_CR_Sort DEFAULT (0),
        CONSTRAINT UQ_sel_CycleReadiness UNIQUE (CycleId, LevelCode)
    );
    PRINT '  sel.CycleReadiness                created';
END
ELSE PRINT '  sel.CycleReadiness                skipped';
GO

/* --- sel.CycleRequirement -------------------------------------------------------
   A requirement the cycle adds on top of its frameworks, or a per-cycle override of
   a framework item's weight or must flag.                                            */
IF OBJECT_ID('sel.CycleRequirement') IS NULL
BEGIN
    CREATE TABLE sel.CycleRequirement
    (
        CycleRequirementId int       IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleRequirement PRIMARY KEY,
        CycleId      int           NOT NULL CONSTRAINT FK_sel_CRQ_Cycle REFERENCES sel.Cycle(CycleId),
        DevEventId   int           NOT NULL CONSTRAINT FK_sel_CRQ_Event REFERENCES sel.DevEvent(DevEventId),
        LevelCode    nvarchar(20)  NULL,
        Weight       decimal(9,4)  NOT NULL CONSTRAINT DF_sel_CRQ_Weight DEFAULT (0),
        IsMust       bit           NOT NULL CONSTRAINT DF_sel_CRQ_Must   DEFAULT (0),
        SortOrder    int           NOT NULL CONSTRAINT DF_sel_CRQ_Sort   DEFAULT (0),
        CONSTRAINT UQ_sel_CycleRequirement UNIQUE (CycleId, DevEventId, LevelCode)
    );
    PRINT '  sel.CycleRequirement              created';
END
ELSE PRINT '  sel.CycleRequirement              skipped';
GO

/* --- processes and stages ------------------------------------------------------- */
IF OBJECT_ID('sel.ProcessType') IS NULL
BEGIN
    CREATE TABLE sel.ProcessType
    (
        ProcessTypeCode nvarchar(30) NOT NULL CONSTRAINT PK_sel_ProcessType PRIMARY KEY,
        Name        nvarchar(120) NOT NULL,
        Description nvarchar(400) NULL,
        /* Whether a design may carry two of these. */
        AllowsRepeat bit          NOT NULL CONSTRAINT DF_sel_ProcessType_Repeat DEFAULT (0),
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_ProcessType_Sort   DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sel_ProcessType_Act    DEFAULT (1)
    );
    PRINT '  sel.ProcessType                   created';
END
ELSE PRINT '  sel.ProcessType                   skipped';
GO

IF OBJECT_ID('sel.StageKind') IS NULL
BEGIN
    CREATE TABLE sel.StageKind
    (
        StageKindCode   nvarchar(30) NOT NULL CONSTRAINT PK_sel_StageKind PRIMARY KEY,
        ProcessTypeCode nvarchar(30) NOT NULL CONSTRAINT FK_sel_StageKind_Process REFERENCES sel.ProcessType(ProcessTypeCode),
        Name        nvarchar(120) NOT NULL,
        /* The route segment the stage screen lives at. */
        RouteKey    nvarchar(60)  NOT NULL,
        ScreenCode  nvarchar(160) NULL,
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_StageKind_Sort DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sel_StageKind_Act  DEFAULT (1)
    );
    PRINT '  sel.StageKind                     created';
END
ELSE PRINT '  sel.StageKind                     skipped';
GO

IF OBJECT_ID('sel.CycleProcess') IS NULL
BEGIN
    CREATE TABLE sel.CycleProcess
    (
        CycleProcessId  int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleProcess PRIMARY KEY,
        CycleId         int          NOT NULL CONSTRAINT FK_sel_CP_Cycle   REFERENCES sel.Cycle(CycleId),
        ProcessTypeCode nvarchar(30) NOT NULL CONSTRAINT FK_sel_CP_Type    REFERENCES sel.ProcessType(ProcessTypeCode),
        Name        nvarchar(200) NOT NULL,
        StartDate   date          NULL,
        EndDate     date          NULL,
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_CP_Sort DEFAULT (0)
    );
    CREATE INDEX IX_sel_CP_Cycle ON sel.CycleProcess (CycleId, SortOrder);
    PRINT '  sel.CycleProcess                  created';
END
ELSE PRINT '  sel.CycleProcess                  skipped';
GO

IF OBJECT_ID('sel.CycleStage') IS NULL
BEGIN
    CREATE TABLE sel.CycleStage
    (
        CycleStageId    int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleStage PRIMARY KEY,
        CycleProcessId  int          NOT NULL CONSTRAINT FK_sel_CS_Process REFERENCES sel.CycleProcess(CycleProcessId),
        StageKindCode   nvarchar(30) NOT NULL CONSTRAINT FK_sel_CS_Kind    REFERENCES sel.StageKind(StageKindCode),
        Name        nvarchar(200) NOT NULL,
        StartDate   date          NULL,
        EndDate     date          NULL,
        /* Who performs it, from the managed management-level list. */
        PerformerLevelValueId int  NULL CONSTRAINT FK_sel_CS_Performer REFERENCES cfg.DomainValue(DomainValueId),
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_CS_Sort DEFAULT (0)
    );
    CREATE INDEX IX_sel_CS_Process ON sel.CycleStage (CycleProcessId, SortOrder);
    PRINT '  sel.CycleStage                    created';
END
ELSE PRINT '  sel.CycleStage                    skipped';
GO

/* --- the pool snapshot ----------------------------------------------------------
   Written at open and never recomputed.                                             */
IF OBJECT_ID('sel.CycleCandidate') IS NULL
BEGIN
    CREATE TABLE sel.CycleCandidate
    (
        CycleCandidateId bigint      IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleCandidate PRIMARY KEY,
        CycleId     int           NOT NULL CONSTRAINT FK_sel_CCand_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo nvarchar(30)  NOT NULL,
        /* ELIGIBLE | EXISTING POOL | OUTSIDE CRITERIA — persists through every stage. */
        SourceCode  nvarchar(30)  NOT NULL,
        /* The organisation as it was when the snapshot was taken, so row-level security
           on a historic cycle answers the question the cycle asked. */
        OrgCode     nvarchar(40)  NOT NULL,
        AddedByLogin nvarchar(128) NULL,
        AddedOnUtc  datetime2(3)  NOT NULL CONSTRAINT DF_sel_CCand_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_CycleCandidate UNIQUE (CycleId, PersonnelNo)
    );
    CREATE INDEX IX_sel_CCand_Cycle ON sel.CycleCandidate (CycleId, OrgCode) INCLUDE (PersonnelNo, SourceCode);
    CREATE INDEX IX_sel_CCand_Person ON sel.CycleCandidate (PersonnelNo) INCLUDE (CycleId, SourceCode);
    PRINT '  sel.CycleCandidate                created';
END
ELSE PRINT '  sel.CycleCandidate                skipped';
GO

/* --- sel.CycleCandidateTrace ----------------------------------------------------
   For any pooled person, each criterion and the value that satisfied it.  An auditor
   must be able to explain why a named person was pooled without changing anything.    */
IF OBJECT_ID('sel.CycleCandidateTrace') IS NULL
BEGIN
    CREATE TABLE sel.CycleCandidateTrace
    (
        CycleCandidateTraceId bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleCandidateTrace PRIMARY KEY,
        CycleId      int           NOT NULL,
        PersonnelNo  nvarchar(30)  NOT NULL,
        CriterionId  int           NULL,
        SetLabel     nvarchar(10)  NULL,
        FieldName    nvarchar(128) NULL,
        OperatorName nvarchar(60)  NULL,
        TestedValue  nvarchar(400) NULL,   -- what the criterion asked for
        ActualValue  nvarchar(400) NULL,   -- what the person's record held
        Passed       bit           NULL,
        CapturedOnUtc datetime2(3) NOT NULL CONSTRAINT DF_sel_CCT_On DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_sel_CCT ON sel.CycleCandidateTrace (CycleId, PersonnelNo);
    PRINT '  sel.CycleCandidateTrace           created';
END
ELSE PRINT '  sel.CycleCandidateTrace           skipped';
GO

/* --- sel.ProcessCandidate -------------------------------------------------------
   Who a given process is working on.  Succession identify works on the survivors of
   calibration, not on the whole pool.                                                */
IF OBJECT_ID('sel.ProcessCandidate') IS NULL
BEGIN
    CREATE TABLE sel.ProcessCandidate
    (
        ProcessCandidateId bigint   IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_ProcessCandidate PRIMARY KEY,
        CycleProcessId int          NOT NULL CONSTRAINT FK_sel_PC_Process REFERENCES sel.CycleProcess(CycleProcessId),
        PersonnelNo    nvarchar(30) NOT NULL,
        SourceCode     nvarchar(30) NOT NULL,
        AddedByLogin   nvarchar(128) NULL,
        AddedOnUtc     datetime2(3) NOT NULL CONSTRAINT DF_sel_PC_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_ProcessCandidate UNIQUE (CycleProcessId, PersonnelNo)
    );
    CREATE INDEX IX_sel_PC_Person ON sel.ProcessCandidate (PersonnelNo);
    PRINT '  sel.ProcessCandidate              created';
END
ELSE PRINT '  sel.ProcessCandidate              skipped';
GO

/* --- sel.CandidateDecision ------------------------------------------------------
   Append only.  Every change, including clearing, is logged — the current decision is
   the latest row, so the history is never overwritten.                               */
IF OBJECT_ID('sel.CandidateDecision') IS NULL
BEGIN
    CREATE TABLE sel.CandidateDecision
    (
        DecisionId    bigint        IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CandidateDecision PRIMARY KEY,
        CycleId       int           NOT NULL CONSTRAINT FK_sel_CD_Cycle   REFERENCES sel.Cycle(CycleId),
        CycleProcessId int          NULL CONSTRAINT FK_sel_CD_Process     REFERENCES sel.CycleProcess(CycleProcessId),
        CycleStageId  int           NULL CONSTRAINT FK_sel_CD_Stage       REFERENCES sel.CycleStage(CycleStageId),
        PersonnelNo   nvarchar(30)  NOT NULL,
        /* The decision word, from cfg.Domain 'DECISION'. */
        DecisionValueId int         NOT NULL CONSTRAINT FK_sel_CD_Decision REFERENCES cfg.DomainValue(DomainValueId),
        Reason        nvarchar(600) NULL,
        /* The management level the decision was taken at. */
        PerformerLevelValueId int   NULL CONSTRAINT FK_sel_CD_Performer REFERENCES cfg.DomainValue(DomainValueId),
        ActorLogin    nvarchar(128) NOT NULL,
        DecidedOnUtc  datetime2(3)  NOT NULL CONSTRAINT DF_sel_CD_On DEFAULT (SYSUTCDATETIME()),
        /* Stamped on every decision taken while test mode ignores the stage window. */
        IsTest        bit           NOT NULL CONSTRAINT DF_sel_CD_Test DEFAULT (0),
        /* Denormalised for the log's organisation filter and row-level security. */
        OrgCode       nvarchar(40)  NULL
    );
    CREATE INDEX IX_sel_CD_Cycle  ON sel.CandidateDecision (CycleId, CycleStageId, PersonnelNo, DecisionId DESC);
    CREATE INDEX IX_sel_CD_Person ON sel.CandidateDecision (PersonnelNo, DecidedOnUtc DESC);
    CREATE INDEX IX_sel_CD_When   ON sel.CandidateDecision (DecidedOnUtc DESC) INCLUDE (CycleId, PersonnelNo, DecisionValueId, ActorLogin);
    PRINT '  sel.CandidateDecision             created';
END
ELSE PRINT '  sel.CandidateDecision             skipped';
GO

/* --- the wizard, its recipes and its validation --------------------------------- */
IF OBJECT_ID('sel.WizardStep') IS NULL
BEGIN
    CREATE TABLE sel.WizardStep
    (
        WizardStepId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_WizardStep PRIMARY KEY,
        StepNo      int           NOT NULL CONSTRAINT UQ_sel_WizardStep_No UNIQUE,
        StepCode    nvarchar(40)  NOT NULL CONSTRAINT UQ_sel_WizardStep_Code UNIQUE,
        Caption     nvarchar(120) NOT NULL,
        Description nvarchar(400) NULL,
        IsSkippable bit           NOT NULL CONSTRAINT DF_sel_WizardStep_Skip DEFAULT (0),
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_WizardStep_Sort DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sel_WizardStep_Act  DEFAULT (1)
    );
    PRINT '  sel.WizardStep                    created';
END
ELSE PRINT '  sel.WizardStep                    skipped';
GO

IF OBJECT_ID('sel.CycleSkippedStep') IS NULL
BEGIN
    CREATE TABLE sel.CycleSkippedStep
    (
        CycleId  int NOT NULL CONSTRAINT FK_sel_CSS_Cycle REFERENCES sel.Cycle(CycleId),
        StepNo   int NOT NULL,
        SkippedByLogin nvarchar(128) NULL,
        SkippedOnUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_CSS_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sel_CycleSkippedStep PRIMARY KEY (CycleId, StepNo)
    );
    PRINT '  sel.CycleSkippedStep              created';
END
ELSE PRINT '  sel.CycleSkippedStep              skipped';
GO

IF OBJECT_ID('sel.CycleRecipe') IS NULL
BEGIN
    CREATE TABLE sel.CycleRecipe
    (
        RecipeId    int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleRecipe PRIMARY KEY,
        RecipeCode  nvarchar(40)  NOT NULL CONSTRAINT UQ_sel_CycleRecipe_Code UNIQUE,
        Name        nvarchar(160) NOT NULL,
        Description nvarchar(600) NULL,
        /* A Talent Cycle asks a second question about job suffixes; Start New asks none. */
        AsksJobSuffix bit         NOT NULL CONSTRAINT DF_sel_CycleRecipe_Suffix DEFAULT (0),
        IsCopy      bit           NOT NULL CONSTRAINT DF_sel_CycleRecipe_Copy   DEFAULT (0),
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_CycleRecipe_Sort   DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sel_CycleRecipe_Act    DEFAULT (1)
    );
    PRINT '  sel.CycleRecipe                   created';
END
ELSE PRINT '  sel.CycleRecipe                   skipped';
GO

IF OBJECT_ID('sel.CycleRecipeProcess') IS NULL
BEGIN
    CREATE TABLE sel.CycleRecipeProcess
    (
        RecipeProcessId int         IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_CycleRecipeProcess PRIMARY KEY,
        RecipeId        int          NOT NULL CONSTRAINT FK_sel_CRP_Recipe  REFERENCES sel.CycleRecipe(RecipeId),
        ProcessTypeCode nvarchar(30) NOT NULL CONSTRAINT FK_sel_CRP_Process REFERENCES sel.ProcessType(ProcessTypeCode),
        Name            nvarchar(200) NULL,
        SortOrder       int          NOT NULL CONSTRAINT DF_sel_CRP_Sort DEFAULT (0)
    );
    PRINT '  sel.CycleRecipeProcess            created';
END
ELSE PRINT '  sel.CycleRecipeProcess            skipped';
GO

IF OBJECT_ID('sel.CycleRecipeSkip') IS NULL
BEGIN
    CREATE TABLE sel.CycleRecipeSkip
    (
        RecipeId int NOT NULL CONSTRAINT FK_sel_CRS_Recipe REFERENCES sel.CycleRecipe(RecipeId),
        StepNo   int NOT NULL,
        CONSTRAINT PK_sel_CycleRecipeSkip PRIMARY KEY (RecipeId, StepNo)
    );
    PRINT '  sel.CycleRecipeSkip               created';
END
ELSE PRINT '  sel.CycleRecipeSkip               skipped';
GO

/* --- sel.ValidationRule ---------------------------------------------------------
   What blocks opening a cycle.  Every sentence the review step shows comes from here;
   none of them is a validation attribute in C#.                                       */
IF OBJECT_ID('sel.ValidationRule') IS NULL
BEGIN
    CREATE TABLE sel.ValidationRule
    (
        ValidationRuleId int         IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_ValidationRule PRIMARY KEY,
        RuleCode    nvarchar(60)  NOT NULL CONSTRAINT UQ_sel_ValidationRule_Code UNIQUE,
        StepNo      int           NULL,               -- the step whose button fixes it
        Sentence    nvarchar(600) NOT NULL,
        Severity    nvarchar(20)  NOT NULL CONSTRAINT DF_sel_ValidationRule_Sev DEFAULT (N'BLOCK'),
        SortOrder   int           NOT NULL CONSTRAINT DF_sel_ValidationRule_Sort DEFAULT (0),
        IsActive    bit           NOT NULL CONSTRAINT DF_sel_ValidationRule_Act  DEFAULT (1)
    );
    PRINT '  sel.ValidationRule                created';
END
ELSE PRINT '  sel.ValidationRule                skipped';
GO

/* =====================================================================================
   Functions
   ===================================================================================== */

/* sel.fn_CycleStatusCode — the status word, for procedures that must refuse a Closed
   cycle.  "A closed cycle is never changed, only copied."                            */
CREATE OR ALTER FUNCTION sel.fn_CycleStatusCode (@CycleId int)
RETURNS nvarchar(60)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @c nvarchar(60);
    SELECT @c = dv.ValueCode
    FROM sel.Cycle cy JOIN cfg.DomainValue dv ON dv.DomainValueId = cy.StatusValueId
    WHERE cy.CycleId = @CycleId;
    RETURN @c;
END
GO
PRINT '  sel.fn_CycleStatusCode            applied';
GO

/* sel.fn_StageState — future / open / closed / undated against the as-of date, with
   test mode ignoring the window.  One implementation: the tab strip, the lock message,
   the write guard and the IDP countdown all read the same answer.                     */
CREATE OR ALTER FUNCTION sel.fn_StageState (@CycleStageId int, @AsOf date, @TestMode bit)
RETURNS nvarchar(20)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @s date, @e date;
    SELECT @s = StartDate, @e = EndDate FROM sel.CycleStage WHERE CycleStageId = @CycleStageId;

    IF @s IS NULL AND @e IS NULL RETURN N'UNDATED';
    IF @TestMode = 1              RETURN N'OPEN';
    IF @s IS NOT NULL AND @AsOf < @s RETURN N'FUTURE';
    IF @e IS NOT NULL AND @AsOf > @e RETURN N'CLOSED';
    RETURN N'OPEN';
END
GO
PRINT '  sel.fn_StageState                 applied';
GO

/* sel.fn_CycleConfiguredTracks — the five tracks the design list shows instead of a
   percentage, so you can see which step is missing without reading a number.          */
CREATE OR ALTER FUNCTION sel.fn_CycleConfiguredTracks (@CycleId int)
RETURNS TABLE
AS
RETURN
    SELECT TrackCode = N'CYCLE',      SortOrder = 1,
           IsSet = CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.Cycle c WHERE c.CycleId = @CycleId
                                      AND c.StartDate IS NOT NULL AND c.EndDate IS NOT NULL
                                      AND NULLIF(LTRIM(RTRIM(c.Name)), N'') IS NOT NULL) THEN 1 ELSE 0 END)
    UNION ALL
    /* Every branch converts: int outranks bit in a UNION, so one untyped branch would
       make the whole column an int and the flag would stop reading as a flag. */
    SELECT N'POOL', 2,
           CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.CycleCriterionSet s WHERE s.CycleId = @CycleId) THEN 1 ELSE 0 END)
    UNION ALL
    SELECT N'FRAMEWORK', 3,
           CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.CycleFramework f WHERE f.CycleId = @CycleId) THEN 1 ELSE 0 END)
    UNION ALL
    SELECT N'READINESS', 4,
           CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.CycleReadiness r WHERE r.CycleId = @CycleId) THEN 1 ELSE 0 END)
    UNION ALL
    SELECT N'STAGES', 5,
           CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.CycleProcess p WHERE p.CycleId = @CycleId) THEN 1 ELSE 0 END);
GO
PRINT '  sel.fn_CycleConfiguredTracks      applied';
GO

/* sel.fn_CurrentDecision — the latest decision for one person in one stage.
   Clearing writes a row too, so "no decision" is the absence of a row or a row whose
   decision word is the cleared one.                                                   */
CREATE OR ALTER FUNCTION sel.fn_CurrentDecision (@CycleStageId int, @PersonnelNo nvarchar(30))
RETURNS int
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @id int;
    SELECT TOP (1) @id = d.DecisionValueId
    FROM sel.CandidateDecision d
    WHERE d.CycleStageId = @CycleStageId AND d.PersonnelNo = @PersonnelNo
    ORDER BY d.DecisionId DESC;
    RETURN @id;
END
GO
PRINT '  sel.fn_CurrentDecision            applied';
GO

/* sel.usp_ProcessType_List — what step 5 may add, and whether each may be added twice.
   AllowsRepeat is a column, not a rule in C#. */
CREATE OR ALTER PROCEDURE sel.usp_ProcessType_List
    @LoginName nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ProcessTypeCode, Name, Description, AllowsRepeat, SortOrder
    FROM sel.ProcessType WHERE IsActive = 1 ORDER BY SortOrder, Name;

    SELECT StageKindCode, ProcessTypeCode, Name, RouteKey, ScreenCode, SortOrder
    FROM sel.StageKind WHERE IsActive = 1 ORDER BY ProcessTypeCode, SortOrder;
END
GO
PRINT '  sel.usp_ProcessType_List          applied';
GO

PRINT '== 05_cycle complete =================================================';
GO
