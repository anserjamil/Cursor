/* =====================================================================================
   db/dev/02_demo_content.sql — load the mock sources and build something to look at
   -------------------------------------------------------------------------------------
   Everything below goes through the same procedures the application calls.  Nothing is
   inserted into sel.* by hand, so if a rule refuses something here it would refuse it on
   the screen too — which is the point of writing the fixture this way.

   DEVELOPMENT ONLY.  It creates a cycle, opens it, and grants organisations to the seeded
   users.  It is never part of a deployment.
   ===================================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() <> N'DB02'
BEGIN
    RAISERROR(N'This script expects DB02. There is one database and that is its name.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* -------------------------------------------------------------------------------------
   Re-runnable.  Everything this fixture creates is cleared first, so running it twice
   leaves one cycle and one framework rather than two of each.  It only ever touches what
   it made: the demo cycle, the demo framework and the demo events.
   ------------------------------------------------------------------------------------- */
PRINT N'dev/02 — clearing anything an earlier run left';

DECLARE @oldCycle int = (SELECT CycleId FROM sel.Cycle WHERE CycleCode LIKE N'TR-2%');
IF @oldCycle IS NOT NULL
BEGIN
    DELETE FROM sel.IdpApproval    WHERE CycleId = @oldCycle;
    DELETE FROM sel.IdpCoverage    WHERE CycleId = @oldCycle;
    DELETE FROM sel.IdpNote        WHERE CycleId = @oldCycle;
    DELETE FROM sel.IdpItem        WHERE CycleId = @oldCycle;
    DELETE FROM sel.IdpTarget      WHERE CycleId = @oldCycle;
    DELETE FROM sel.CandidateDecision     WHERE CycleId = @oldCycle;
    DELETE FROM sel.ProcessCandidate      WHERE CycleProcessId IN (SELECT CycleProcessId FROM sel.CycleProcess WHERE CycleId = @oldCycle);
    DELETE FROM sel.CandidateFlag         WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleCandidateTrace   WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleCandidate        WHERE CycleId = @oldCycle;
    DELETE FROM sel.SuccessionSlot        WHERE CycleId = @oldCycle;
    DELETE FROM sel.ReadinessHistory      WHERE CycleId = @oldCycle;
    DELETE FROM sel.SuccessionPlanRow     WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleStage            WHERE CycleProcessId IN (SELECT CycleProcessId FROM sel.CycleProcess WHERE CycleId = @oldCycle);
    DELETE FROM sel.CycleProcess          WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleCriterion        WHERE CriterionSetId IN (SELECT CriterionSetId FROM sel.CycleCriterionSet WHERE CycleId = @oldCycle);
    DELETE FROM sel.CycleCriterionSet     WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleReadiness        WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleRequirement      WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleFramework        WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleSkippedStep      WHERE CycleId = @oldCycle;
    DELETE FROM sel.CycleJobSuffix        WHERE CycleId = @oldCycle;
    DELETE FROM sel.Cycle                 WHERE CycleId = @oldCycle;
END;

DELETE FROM sel.DevFrameworkItem WHERE DevFrameworkId IN (SELECT DevFrameworkId FROM sel.DevFramework WHERE FrameworkCode = N'FW-LEADERSHIP');
DELETE FROM sel.DevFramework     WHERE FrameworkCode = N'FW-LEADERSHIP';
DELETE FROM sel.DevEquivalence   WHERE MainItemCode = N'CRS-LEAD-02';
DELETE FROM sel.DevEventCondition    WHERE SetId IN (SELECT SetId FROM sel.DevEventConditionSet WHERE DevEventId IN (SELECT DevEventId FROM sel.DevEvent WHERE EventCode LIKE N'EV-%'));
DELETE FROM sel.DevEventConditionSet WHERE DevEventId IN (SELECT DevEventId FROM sel.DevEvent WHERE EventCode LIKE N'EV-%');
DELETE FROM sel.DevEvent             WHERE EventCode LIKE N'EV-%';

/* The exception log is a record of one load, not a running tally across re-runs of the
   fixture. On a real server it is never cleared. */
DELETE FROM stg.LoadException;
GO

DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);

PRINT N'dev/02 — discovering the mapped tables';
EXEC sel.usp_TableMapping_Discover @LoginName = @admin, @SourceKey = NULL, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);

PRINT N'dev/02 — loading the roster';
EXEC sel.usp_Roster_Load @LoginName = @admin, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

PRINT N'dev/02 — syncing the evidence';
EXEC sel.usp_Evidence_SyncAll @LoginName = @admin, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

PRINT N'dev/02 — re-reading the roster columns';
EXEC sel.usp_RosterField_Sync @LoginName = @admin, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

EXEC sel.usp_ColumnCatalog_Sync @LoginName = @admin, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

/* ---- the alias that answers the two rows the load set aside ---------------------
   The answer to a personnel number the roster does not carry is an exact statement that
   this key is that person. Never a fuzzy match on a name.                             */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @someone nvarchar(30) = (SELECT TOP (1) PersonnelNo FROM sel.Employee ORDER BY PersonnelNo);

EXEC sel.usp_PersonAlias_Save @LoginName = @admin, @SourceKey = N'COURSE',
     @AliasKey = N'LEGACY-7741', @PersonnelNo = @someone,
     @Note = N'The legacy learning system used its own number for this person.',
     @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
/* LEGACY-7742 is deliberately left unmapped, so the load-exceptions screen has
   something open on it. */

/* An alias only changes anything on the next sync: the rows it unlocks are read then,
   and the exceptions it answered are closed then. */
EXEC sel.usp_Evidence_SyncAll @LoginName = @admin, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

DECLARE @exId bigint;
DECLARE fixed CURSOR LOCAL FAST_FORWARD FOR
    SELECT LoadExceptionId FROM stg.LoadException
    WHERE IsResolved = 0 AND KeyText = N'LEGACY-7741';
OPEN fixed;
FETCH NEXT FROM fixed INTO @exId;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sel.usp_LoadException_Resolve @LoginName = @admin, @LoadExceptionId = @exId,
         @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @p;
    FETCH NEXT FROM fixed INTO @exId;
END;
CLOSE fixed; DEALLOCATE fixed;
GO

/* ---- categorise the discovered catalogue ----------------------------------------
   Item codes are discovered by the loads, not authored, and arrive flagged for review.
   Giving them a category is what takes the flag off. Two are deliberately left flagged,
   because that is the state an administrator actually walks into.                     */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @ciId int, @ciCode nvarchar(60), @ciName nvarchar(300), @ciKind nvarchar(30), @ciCat nvarchar(60);

DECLARE cat CURSOR LOCAL FAST_FORWARD FOR
    SELECT ci.CatalogItemId, ci.ItemCode, ci.Name, ci.KindCode,
           /* The categories are cfg.DomainValue rows, not words invented here. */
           CategoryCode = CASE WHEN ci.ItemCode LIKE N'CRS-LEAD%' THEN N'DIRECTOR_COURSE'
                               WHEN ci.ItemCode LIKE N'CRS-%'     THEN N'COURSE'
                               WHEN ci.ItemCode LIKE N'ASM-%'     THEN N'ASSESSMENT'
                               WHEN ci.ItemCode LIKE N'SVY-%'     THEN N'FEEDBACK360'
                               ELSE N'COVERAGE_DAYS' END
    FROM sel.CatalogItem ci
    WHERE ci.NeedsReview = 1
      AND ci.ItemCode NOT IN (N'CRS-DIG-01', N'CRS-FIN-01');   /* left for somebody to look at */
OPEN cat;
FETCH NEXT FROM cat INTO @ciId, @ciCode, @ciName, @ciKind, @ciCat;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sel.usp_CatalogItem_Save @LoginName = @admin, @CatalogItemId = @ciId,
         @ItemCode = @ciCode, @Name = @ciName, @KindCode = @ciKind,
         @CategoryCode = @ciCat, @NeedsReview = 0, @IsActive = 1, @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @ciCode + N': ' + @p;
    FETCH NEXT FROM cat INTO @ciId, @ciCode, @ciName, @ciKind, @ciCat;
END;
CLOSE cat; DEALLOCATE cat;

/* Categorising a code is the answer to the exception that reported it, so the exception
   is closed here rather than left open forever. The two codes left flagged keep theirs,
   which is what an administrator should walk into. */
DECLARE @exId2 bigint;
DECLARE done2 CURSOR LOCAL FAST_FORWARD FOR
    SELECT x.LoadExceptionId
    FROM stg.LoadException x
    WHERE x.IsResolved = 0 AND x.ReasonCode = N'ITEM_CODE_UNKNOWN'
      AND EXISTS (SELECT 1 FROM sel.CatalogItem ci
                  WHERE ci.NeedsReview = 0 AND x.KeyText = ci.ItemCode);
OPEN done2;
FETCH NEXT FROM done2 INTO @exId2;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sel.usp_LoadException_Resolve @LoginName = @admin, @LoadExceptionId = @exId2,
         @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @p;
    FETCH NEXT FROM done2 INTO @exId2;
END;
CLOSE done2; DEALLOCATE done2;
GO

/* =====================================================================================
   Roster fields.  Everything is discovered switched off; these are the ones a criterion
   may name.  The sensitive ones are marked, and marking one sensitive is what refuses it
   as a filter while leaving it readable on a person's record.
   ===================================================================================== */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @fid int, @fname nvarchar(128), @caption nvarchar(200), @grp nvarchar(100), @sens bit;

DECLARE fields CURSOR LOCAL FAST_FORWARD FOR
    SELECT f.RosterFieldId, f.FieldName, x.Caption, x.GroupName, x.IsSensitive
    FROM sel.RosterField f
    JOIN (VALUES
        (N'OrgCode',           N'Organisation',            N'Where they sit',     0),
        (N'JobTitle',          N'Job title',               N'Where they sit',     0),
        (N'PermJobSuffix',     N'Permanent job suffix',    N'Where they sit',     0),
        (N'CurrentJobSuffix',  N'Current job suffix',      N'Where they sit',     0),
        (N'GradeCode',         N'Grade',                   N'Where they sit',     0),
        (N'ManagementLevel',   N'Management level',        N'Where they sit',     0),
        (N'HireDate',          N'Hire date',               N'Service',            0),
        (N'PromotionDate',     N'Last promoted',           N'Service',            0),
        (N'ActiveInd',         N'Active',                  N'Service',            0),
        (N'PermChiefInd',      N'Holds a chief position',  N'Service',            0),
        (N'Location',          N'Location',                N'Where they sit',     0),
        (N'ContractType',      N'Contract type',           N'Service',            0),
        (N'DaysCovered',       N'Coverage days',           N'What they have done',0),
        (N'PerformanceAvg3',   N'Three-year performance',  N'What they have done',0),
        (N'CoursesCompleted',  N'Courses completed',       N'What they have done',0),
        (N'DirectorActingDays',N'Director acting days',    N'What they have done',0),
        (N'TenureYears',       N'Tenure in years',         N'Service',            0),
        /* Readable on a record. Refused as a filter, and the refusal says why. */
        (N'BirthDate',         N'Date of birth',           N'Personal',           1),
        (N'Gender',            N'Gender',                  N'Personal',           1),
        (N'Nationality',       N'Nationality',             N'Personal',           1),
        (N'SpecialNeedInd',    N'Special need',            N'Personal',           1)
    ) x (FieldName, Caption, GroupName, IsSensitive) ON x.FieldName = f.FieldName;

OPEN fields;
FETCH NEXT FROM fields INTO @fid, @fname, @caption, @grp, @sens;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sel.usp_RosterField_Save @LoginName = @admin, @RosterFieldId = @fid,
         @Caption = @caption, @IsEnabled = 1, @IsSensitive = @sens, @GroupName = @grp,
         @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @fname + N': ' + @p;
    FETCH NEXT FROM fields INTO @fid, @fname, @caption, @grp, @sens;
END;
CLOSE fields; DEALLOCATE fields;

DECLARE @enabled int = (SELECT COUNT(*) FROM sel.RosterField WHERE IsEnabled = 1);
DECLARE @sensitive int = (SELECT COUNT(*) FROM sel.RosterField WHERE IsSensitive = 1);
PRINT N'  roster fields enabled     ' + CONVERT(nvarchar(10), @enabled)
    + N' (' + CONVERT(nvarchar(10), @sensitive) + N' sensitive, refused as filters)';
GO

/* =====================================================================================
   The development events.  Each is a question; the rule under it is how the question
   gets answered from the data.
   ===================================================================================== */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);

DECLARE @events TABLE
(
    EventCode nvarchar(60), Name nvarchar(300), Descr nvarchar(600), KindCode nvarchar(30),
    ItemCode nvarchar(60), EventTypeCode nvarchar(60), PartCode nvarchar(60),
    MeasureCode nvarchar(60), PassValue nvarchar(120), SumFloor decimal(18,4),
    ValidityMonths int
);
INSERT @events VALUES
 (N'EV-SAFE-FND', N'Process safety, foundation', N'The foundation safety course, and it expires.',
  N'COURSE', N'CRS-SAFE-01', N'COURSE', N'COURSE', N'COMPLETION', N'Completed', NULL, 24),
 (N'EV-SAFE-ADV', N'Process safety, advanced', NULL,
  N'COURSE', N'CRS-SAFE-02', N'COURSE', N'COURSE', N'COMPLETION', N'Completed', NULL, 24),
 (N'EV-LEAD-TEAM', N'Leading a team', N'The first leadership course.',
  N'COURSE', N'CRS-LEAD-01', N'COURSE', N'COURSE', N'COMPLETION', N'Completed', NULL, NULL),
 (N'EV-LEAD-LEAD', N'Leading leaders', N'The second leadership course. An older code also counts.',
  N'COURSE', N'CRS-LEAD-02', N'COURSE', N'COURSE', N'COMPLETION', N'Completed', NULL, NULL),
 (N'EV-CAPITAL', N'Capital project appraisal', NULL,
  N'COURSE', N'CRS-CAP-02', N'COURSE', N'COURSE', N'COMPLETION', N'Completed', NULL, NULL),
 (N'EV-ASM-360', N'360 assessment, second round', N'Met at 75 or better, on its own scale.',
  N'ASSESSMENT', N'ASM-360-02', N'ASSESSMENT', N'ASSESSMENT', N'SCORE', N'Completed', NULL, NULL),
 (N'EV-ASM-COG', N'Cognitive assessment', NULL,
  N'ASSESSMENT', N'ASM-COG-01', N'ASSESSMENT', N'ASSESSMENT', N'SCORE', N'Completed', NULL, NULL),
 (N'EV-ASM-LEAD', N'Leadership assessment', NULL,
  N'ASSESSMENT', N'ASM-LEAD-01', N'ASSESSMENT', N'ASSESSMENT', N'SCORE', N'Completed', NULL, NULL),
 (N'EV-ACT-DIR', N'Acting in a director position', N'Ninety days of it, added up across spells.',
  N'COVERAGE', N'DIR1', N'ASSIGNMENT', N'EXPERIENCE', N'DAYS', NULL, 90, NULL),
 (N'EV-ACT-MGR', N'Acting in a manager position', N'Sixty days, added up.',
  N'COVERAGE', N'MGR1', N'ASSIGNMENT', N'EXPERIENCE', N'DAYS', NULL, 60, NULL),
 /* The old code for "Leading leaders". It is a separate event with its own rule and its
    own source, which is exactly what an equivalence needs: the engine reads each
    candidate code against that code's own rule, never against the main one's. */
 (N'EV-LEAD-LEAD-OLD', N'Leading leaders (the old code)', N'The same course before it was renumbered.',
  N'COURSE', N'CRS-LEAD-02B', N'COURSE', N'COURSE', N'COMPLETION', N'Completed', NULL, NULL);

DECLARE @code nvarchar(60), @nm nvarchar(300), @ds nvarchar(600), @kind nvarchar(30),
        @item nvarchar(60), @type nvarchar(60), @part nvarchar(60), @meas nvarchar(60),
        @pass nvarchar(120), @floor decimal(18,4), @months int;

DECLARE ev CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM @events;
OPEN ev;
FETCH NEXT FROM ev INTO @code, @nm, @ds, @kind, @item, @type, @part, @meas, @pass, @floor, @months;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sel.usp_DevEvent_Save @LoginName = @admin, @DevEventId = NULL, @EventCode = @code,
         @Name = @nm, @Description = @ds, @KindCode = @kind, @ItemCode = @item,
         @EventTypeCode = @type, @PartCode = @part, @MeasureCode = @meas, @PhaseCode = NULL,
         @PassValue = @pass, @SumFloor = @floor, @ValidityMonths = @months,
         @RetiredFrom = NULL, @IsActive = 1, @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @code + N': ' + @p;
    FETCH NEXT FROM ev INTO @code, @nm, @ds, @kind, @item, @type, @part, @meas, @pass, @floor, @months;
END;
CLOSE ev; DEALLOCATE ev;

DECLARE @evcount int = (SELECT COUNT(*) FROM sel.DevEvent);
PRINT N'  development events        ' + CONVERT(nvarchar(10), @evcount);
GO

/* ---- rules on two of them, so the rule editor has something real in it -----------
   The 360 assessment asks for a score of 75 or better. The director acting event only
   counts spells recorded as acting, so a permanent assignment does not quietly satisfy
   it. Each condition names a column on that kind's OWN source.                        */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400), @setId int;

DECLARE @asm int = (SELECT DevEventId FROM sel.DevEvent WHERE EventCode = N'EV-ASM-360');
IF @asm IS NOT NULL
BEGIN
    EXEC sel.usp_EventConditionSet_Save @LoginName = @admin, @DevEventId = @asm,
         @SetId = NULL, @SetModeCode = N'ALL', @SetJoinCode = NULL, @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @p;

    SET @setId = (SELECT TOP (1) SetId FROM sel.DevEventConditionSet
                  WHERE DevEventId = @asm ORDER BY SetId DESC);

    EXEC sel.usp_EventCondition_Save @LoginName = @admin, @SetId = @setId, @ConditionId = NULL,
         @FieldName = N'Score', @OperatorCode = N'GE', @Value1 = N'75', @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @p;
END;

DECLARE @act int = (SELECT DevEventId FROM sel.DevEvent WHERE EventCode = N'EV-ACT-DIR');
IF @act IS NOT NULL
BEGIN
    EXEC sel.usp_EventConditionSet_Save @LoginName = @admin, @DevEventId = @act,
         @SetId = NULL, @SetModeCode = N'ALL', @SetJoinCode = NULL, @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @p;

    SET @setId = (SELECT TOP (1) SetId FROM sel.DevEventConditionSet
                  WHERE DevEventId = @act ORDER BY SetId DESC);

    EXEC sel.usp_EventCondition_Save @LoginName = @admin, @SetId = @setId, @ConditionId = NULL,
         @FieldName = N'CoverageType', @OperatorCode = N'EQ', @Value1 = N'ACTING', @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @p;
END;

/* The older leadership code still counts for the current one. It is read with its OWN
   rule and its OWN source, not this event's — which is what makes an equivalence work. */
EXEC sel.usp_Equivalence_Add @LoginName = @admin, @MainItemCode = N'CRS-LEAD-02',
     @EquivalentItemCode = N'CRS-LEAD-02B',
     @Note = N'The course was renumbered in 2019; the old code is the same course.',
     @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

/* =====================================================================================
   A framework with four levels, and a mixture that is deliberately a little off target
   so the gap has something to say.
   ===================================================================================== */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @mix int = (SELECT TOP (1) MixtureModelId FROM sel.MixtureModel ORDER BY SortOrder);

EXEC sel.usp_Framework_Save @LoginName = @admin, @DevFrameworkId = NULL,
     @FrameworkCode = N'FW-LEADERSHIP', @Name = N'Leadership readiness',
     @Description = N'What a person has to have done before they are ready to lead.',
     @StatusCode = N'ACTIVE', @UsesLevels = 1, @MixtureModelId = @mix, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @fw int = (SELECT DevFrameworkId FROM sel.DevFramework WHERE FrameworkCode = N'FW-LEADERSHIP');

DECLARE @items TABLE (EventCode nvarchar(60), LevelNo int, LevelName nvarchar(120),
                      Weight decimal(9,4), IsMust bit);
INSERT @items VALUES
 (N'EV-SAFE-FND',  1, N'Foundation',  1.0, 1),
 (N'EV-LEAD-TEAM', 1, N'Foundation',  2.0, 0),
 (N'EV-ASM-COG',   1, N'Foundation',  1.0, 0),
 (N'EV-SAFE-ADV',  2, N'Practising',  1.0, 0),
 (N'EV-ACT-MGR',   2, N'Practising',  3.0, 0),
 (N'EV-ASM-360',   2, N'Practising',  2.0, 0),
 (N'EV-LEAD-LEAD', 3, N'Leading',     2.0, 1),
 (N'EV-ACT-DIR',   3, N'Leading',     4.0, 0),
 (N'EV-ASM-LEAD',  3, N'Leading',     2.0, 0),
 (N'EV-CAPITAL',   4, N'Directing',   2.0, 0);

DECLARE @ec nvarchar(60), @ln int, @lname nvarchar(120), @w decimal(9,4), @must bit, @eid int;
DECLARE it CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM @items;
OPEN it;
FETCH NEXT FROM it INTO @ec, @ln, @lname, @w, @must;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @eid = (SELECT DevEventId FROM sel.DevEvent WHERE EventCode = @ec);
    IF @eid IS NOT NULL
    BEGIN
        EXEC sel.usp_Framework_SaveItem @LoginName = @admin, @DevFrameworkId = @fw,
             @DevFrameworkItemId = NULL, @DevEventId = @eid, @LevelNo = @ln,
             @LevelName = @lname, @Weight = @w, @IsMust = @must, @Problem = @p OUTPUT;
        IF @p IS NOT NULL PRINT N'  ! ' + @ec + N': ' + @p;
    END;
    FETCH NEXT FROM it INTO @ec, @ln, @lname, @w, @must;
END;
CLOSE it; DEALLOCATE it;

DECLARE @itemcount int = (SELECT COUNT(*) FROM sel.DevFrameworkItem WHERE DevFrameworkId = @fw);
PRINT N'  framework requirements    ' + CONVERT(nvarchar(10), @itemcount);
GO

/* =====================================================================================
   The cycle.  Built through the wizard's own procedures, validated, then opened — which
   is what takes the pool snapshot.
   ===================================================================================== */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @today date = CAST(SYSUTCDATETIME() AS date);
DECLARE @year nvarchar(4) = CONVERT(nvarchar(4), YEAR(@today));

/* Every EXEC argument is a local: SQL Server will not take an expression there. */
DECLARE @cycleCode nvarchar(40) = N'TR-' + @year;
DECLARE @cycleName nvarchar(300) = N'Talent review ' + @year;
DECLARE @endDate date = DATEADD(MONTH, 9, @today);

EXEC sel.usp_Cycle_Save @LoginName = @admin, @CycleId = NULL,
     @CycleCode = @cycleCode, @Name = @cycleName,
     @StartDate = @today, @EndDate = @endDate,
     @OwnerLogin = N'maseera.hrbp', @DelegateLogin = N'maseera.svp',
     @Notes = N'The demonstration cycle. Everything in it was built through the same procedures the screens call.',
     @IncumbentSuffix = N'DIR1', @SuccessorSuffix = N'MGR2',
     @ExistingPoolCode = NULL, @ActiveMembersOnly = 1, @RecipeId = NULL,
     @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

/* ---- the eligible pool: management level, grade, and a performance floor -------- */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @cyc int = (SELECT TOP (1) CycleId FROM sel.Cycle ORDER BY CycleId DESC);
DECLARE @setId int;

EXEC sel.usp_CriterionSet_Save @LoginName = @admin, @CycleId = @cyc, @CriterionSetId = NULL,
     @SetLabel = NULL, @SetModeCode = N'ALL', @SetJoinCode = NULL, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

SET @setId = (SELECT TOP (1) CriterionSetId FROM sel.CycleCriterionSet
              WHERE CycleId = @cyc ORDER BY CriterionSetId DESC);

DECLARE @fActive int = (SELECT RosterFieldId FROM sel.RosterField WHERE FieldName = N'ActiveInd');
DECLARE @fLevel  int = (SELECT RosterFieldId FROM sel.RosterField WHERE FieldName = N'ManagementLevel');
DECLARE @fPerf   int = (SELECT RosterFieldId FROM sel.RosterField WHERE FieldName = N'PerformanceAvg3');

IF @fActive IS NOT NULL
    EXEC sel.usp_Criterion_Save @LoginName = @admin, @CriterionSetId = @setId, @CriterionId = NULL,
         @RosterFieldId = @fActive, @OperatorCode = N'EQ', @Value1 = N'Y', @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

IF @fLevel IS NOT NULL
    EXEC sel.usp_Criterion_Save @LoginName = @admin, @CriterionSetId = @setId, @CriterionId = NULL,
         @RosterFieldId = @fLevel, @OperatorCode = N'IN',
         @Value1 = N'PROFESSIONAL,SUPERVISOR,MANAGER', @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

IF @fPerf IS NOT NULL
    EXEC sel.usp_Criterion_Save @LoginName = @admin, @CriterionSetId = @setId, @CriterionId = NULL,
         @RosterFieldId = @fPerf, @OperatorCode = N'GE', @Value1 = N'55', @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

/* ---- the framework, the ladder, the processes and their stages ------------------ */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @cyc int = (SELECT TOP (1) CycleId FROM sel.Cycle ORDER BY CycleId DESC);
DECLARE @fw  int = (SELECT DevFrameworkId FROM sel.DevFramework WHERE FrameworkCode = N'FW-LEADERSHIP');

EXEC sel.usp_CycleFramework_Assign @LoginName = @admin, @CycleId = @cyc,
     @DevFrameworkId = @fw, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

/* The ladder starts from the preset levels. Each says how much of the framework is
   enough, and no two share a percentage. */
DECLARE @lc nvarchar(20), @ln2 nvarchar(120), @th decimal(9,4), @so int;
DECLARE lv CURSOR LOCAL FAST_FORWARD FOR
    SELECT LevelCode, Name, ThresholdPct, SortOrder FROM sel.ReadinessLevel
    WHERE LevelCode IN (N'R1', N'R2', N'R3', N'R4') ORDER BY SortOrder;
OPEN lv;
FETCH NEXT FROM lv INTO @lc, @ln2, @th, @so;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sel.usp_CycleReadiness_Save @LoginName = @admin, @CycleId = @cyc,
         @CycleReadinessId = NULL, @LevelCode = @lc, @Name = @ln2,
         @ThresholdPct = @th, @SortOrder = @so, @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @lc + N': ' + @p;
    FETCH NEXT FROM lv INTO @lc, @ln2, @th, @so;
END;
CLOSE lv; DEALLOCATE lv;
GO

DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @cyc int = (SELECT TOP (1) CycleId FROM sel.Cycle ORDER BY CycleId DESC);
DECLARE @today date = CAST(SYSUTCDATETIME() AS date);
DECLARE @proc int;

/* The date arithmetic is done once into locals, because SQL Server will not take an
   expression as an EXEC argument. */
DECLARE @m1 date = DATEADD(MONTH, 1, @today), @m2 date = DATEADD(MONTH, 2, @today),
        @m4 date = DATEADD(MONTH, 4, @today), @m5 date = DATEADD(MONTH, 5, @today),
        @m9 date = DATEADD(MONTH, 9, @today);

/* Talent review: identify, review, calibrate. */
EXEC sel.usp_CycleProcess_Save @LoginName = @admin, @CycleId = @cyc, @CycleProcessId = NULL,
     @ProcessTypeCode = N'TALENT_REVIEW', @Name = N'Talent review',
     @StartDate = @today, @EndDate = @m4, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

SET @proc = (SELECT TOP (1) CycleProcessId FROM sel.CycleProcess
             WHERE CycleId = @cyc ORDER BY CycleProcessId DESC);

/* Development, so the plan screens have a stage to sit in. */
EXEC sel.usp_CycleProcess_Save @LoginName = @admin, @CycleId = @cyc, @CycleProcessId = NULL,
     @ProcessTypeCode = N'DEVELOPMENT', @Name = N'Development',
     @StartDate = @m4, @EndDate = @m9,
     @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;

/* Saving the process already creates the stages its process type defines, in order,
   with their windows scheduled across the process. Adding them again here would give the
   cycle two of each — so the performers are set on the stages that exist, through the
   same procedure the screen calls. */
DECLARE @sid int, @sproc int, @skind nvarchar(30), @performer nvarchar(60);
DECLARE @sStart date, @sEnd date;
DECLARE stg CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.CycleStageId, s.CycleProcessId, s.StageKindCode, s.StartDate, s.EndDate
    FROM sel.CycleStage s
    JOIN sel.CycleProcess pr ON pr.CycleProcessId = s.CycleProcessId
    WHERE pr.CycleId = @cyc;
OPEN stg;
FETCH NEXT FROM stg INTO @sid, @sproc, @skind, @sStart, @sEnd;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @performer = CASE WHEN @skind LIKE N'%IDENTIFY' THEN N'MANAGER' ELSE N'DIRECTOR' END;
    /* The windows are passed back deliberately: a save writes the dates it is given, so
       a date left out is a date cleared — which is what lets the screen clear one. */
    EXEC sel.usp_CycleStage_Save @LoginName = @admin, @CycleProcessId = @sproc,
         @CycleStageId = @sid, @StartDate = @sStart, @EndDate = @sEnd,
         @PerformerCode = @performer, @Problem = @p OUTPUT;
    IF @p IS NOT NULL PRINT N'  ! ' + @skind + N': ' + @p;
    FETCH NEXT FROM stg INTO @sid, @sproc, @skind, @sStart, @sEnd;
END;
CLOSE stg; DEALLOCATE stg;
GO

/* ---- organisation grants, so the seeded users see different things -------------- */
DECLARE @admin nvarchar(128) = N'maseera.admin';

/* The HR business partner gets the whole company; the SVP gets one division. The grant
   carries down the tree, so granting a node grants everything beneath it. */
MERGE sec.UserOrgGrant AS t
USING (SELECT u.AppUserId, x.OrgCode
       FROM (VALUES
            /* The HR business partner runs the cycle across the company. */
            (N'maseera.hrbp',    N'ORG'),
            /* The SVP decides for Upstream only, so the same cycle shows them fewer
               people — which is the scope working, not a discrepancy. */
            (N'maseera.svp',     N'ORG-UP'),
            /* The auditor reads everything and changes nothing; the read-only flag on
               the role is what guarantees the second half of that. */
            (N'maseera.auditor', N'ORG')
       ) x (LoginName, OrgCode)
       JOIN sec.AppUser u ON u.LoginName = x.LoginName
       WHERE EXISTS (SELECT 1 FROM sel.OrgNode o WHERE o.OrgCode = x.OrgCode)) AS s
   ON t.AppUserId = s.AppUserId AND t.OrgCode = s.OrgCode
WHEN NOT MATCHED BY TARGET THEN
    INSERT (AppUserId, OrgCode, GrantedByLogin)
    VALUES (s.AppUserId, s.OrgCode, @admin);

PRINT N'  organisation grants set';
GO

/* ---- validate, then open: opening is what takes the snapshot -------------------- */
DECLARE @admin nvarchar(128) = N'maseera.admin';
DECLARE @p nvarchar(400);
DECLARE @cyc int = (SELECT TOP (1) CycleId FROM sel.Cycle ORDER BY CycleId DESC);

PRINT N'dev/02 — validating the design';
EXEC sel.usp_Cycle_Validate @LoginName = @admin, @CycleId = @cyc;

PRINT N'dev/02 — opening the cycle';
EXEC sel.usp_Cycle_Open @LoginName = @admin, @CycleId = @cyc, @AsOf = NULL, @Problem = @p OUTPUT;
IF @p IS NOT NULL PRINT N'  ! ' + @p;
GO

/* ---- the receipt ----------------------------------------------------------------- */
DECLARE @cyc int = (SELECT TOP (1) CycleId FROM sel.Cycle ORDER BY CycleId DESC);

SELECT [What] = N'People on the roster',    [Count] = COUNT(*) FROM sel.Employee
UNION ALL SELECT N'Organisation units',      COUNT(*) FROM sel.OrgNode
UNION ALL SELECT N'Evidence records',        COUNT(*) FROM sel.EmployeeRecord
UNION ALL SELECT N'Coverage rows',           COUNT(*) FROM sel.EmployeeCoverage
UNION ALL SELECT N'Performance rows',        COUNT(*) FROM sel.EmployeePmp
UNION ALL SELECT N'Metric values',           COUNT(*) FROM sel.EmployeeMetric
UNION ALL SELECT N'Roster fields enabled',   COUNT(*) FROM sel.RosterField WHERE IsEnabled = 1
UNION ALL SELECT N'Development events',      COUNT(*) FROM sel.DevEvent
UNION ALL SELECT N'Framework requirements',  COUNT(*) FROM sel.DevFrameworkItem
UNION ALL SELECT N'In the pool',             COUNT(*) FROM sel.CycleCandidate WHERE CycleId = @cyc
UNION ALL SELECT N'Criterion traces',        COUNT(*) FROM sel.CycleCandidateTrace WHERE CycleId = @cyc
UNION ALL SELECT N'Load exceptions open',    COUNT(*) FROM stg.LoadException WHERE IsResolved = 0;
GO

PRINT N'dev/02 — done';
GO
