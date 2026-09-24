/* =====================================================================================
   10_crud.sql  —  one save and one delete per aggregate
   -------------------------------------------------------------------------------------
   Every procedure in this file, without exception:

     1. Checks authority first — sec.fn_CanEditCycle or sec.fn_ScreenAccess — and on
        refusal returns a SENTENCE in @Problem plus a result set with zero rows.  Never a
        bare failure, never an exception as flow control.
     2. Validates against the configuration tables, not literals: a condition's column
        must exist in sel.EvidenceSourceColumn, its operator in cfg.Operator, the number
        of values must equal that operator's Arity, and a criterion's field must be an
        enabled, non-sensitive sel.RosterField.
     3. Writes audit.ChangeLog — table, key, action, before and after, login, UTC time.
     4. Runs in a transaction with SET XACT_ABORT ON where it touches more than one table.
     5. Refuses to touch a Closed cycle.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 10_crud ===========================================================';
GO

/* =====================================================================================
   Reads the cycle screens need
   ===================================================================================== */

/* sel.usp_Cycle_List — the operational home and the design list.  Every read joins the
   viewer's organisation scope: a cycle whose pool is entirely outside your scope shows
   its design but none of its people.                                                   */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_List
    @LoginName   nvarchar(128),
    @AsOf        date = NULL,
    @StatusCode  nvarchar(60) = NULL,
    @Search      nvarchar(200) = NULL,
    @MineOnly    bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT c.CycleId, c.CycleCode, c.Name, c.StartDate, c.EndDate,
           c.OwnerLogin, c.DelegateLogin, c.Notes,
           c.IncumbentSuffix, c.SuccessorSuffix, c.ExistingPoolCode, c.ActiveMembersOnly,
           c.OpenedOnUtc, c.ClosedOnUtc, c.PoolResolvedOnUtc,
           StatusCode = dv.ValueCode, StatusName = dv.Name, StatusRole = dv.SemanticRole,
           OwnerName    = (SELECT TOP (1) u.DisplayName FROM sec.AppUser u WHERE u.LoginName = c.OwnerLogin),
           DelegateName = (SELECT TOP (1) u.DisplayName FROM sec.AppUser u WHERE u.LoginName = c.DelegateLogin),
           /* Figures, scoped to this viewer. */
           PoolCount = (SELECT COUNT(*) FROM sel.CycleCandidate cc
                        JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = cc.OrgCode
                        WHERE cc.CycleId = c.CycleId),
           HighPotentialCount = (SELECT COUNT(DISTINCT d.PersonnelNo)
                        FROM sel.CandidateDecision d
                        JOIN cfg.DomainValue ddv ON ddv.DomainValueId = d.DecisionValueId
                        JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = d.OrgCode
                        WHERE d.CycleId = c.CycleId
                          AND ddv.ValueCode IN (N'VP_VERY_STRONG', N'DIR_VERY_STRONG', N'DIR_STRONG', N'MGR_STRONG')),
           CriteriaCount = (SELECT COUNT(*) FROM sel.CycleCriterion cr
                            JOIN sel.CycleCriterionSet cs ON cs.CriterionSetId = cr.CriterionSetId
                            WHERE cs.CycleId = c.CycleId),
           LevelCount    = (SELECT COUNT(*) FROM sel.CycleReadiness r WHERE r.CycleId = c.CycleId),
           ProcessCount  = (SELECT COUNT(*) FROM sel.CycleProcess p WHERE p.CycleId = c.CycleId),
           CanEdit       = sec.fn_CanEditCycle(@LoginName, c.CycleId),
           EditRefusal   = sec.fn_CycleEditRefusal(@LoginName, c.CycleId)
    FROM sel.Cycle c
    JOIN cfg.DomainValue dv ON dv.DomainValueId = c.StatusValueId
    WHERE (@StatusCode IS NULL OR dv.ValueCode = @StatusCode)
      AND (@Search IS NULL OR c.Name LIKE N'%' + @Search + N'%' OR c.CycleCode LIKE N'%' + @Search + N'%')
      AND (@MineOnly = 0 OR c.OwnerLogin = @LoginName OR c.DelegateLogin = @LoginName)
    ORDER BY CASE dv.ValueCode WHEN N'ACTIVE' THEN 0 WHEN N'DRAFT' THEN 1 ELSE 2 END,
             c.StartDate DESC, c.Name;

    /* The five configured tracks per cycle, so the design list can show which step is
       missing without reducing it to a percentage. */
    SELECT c.CycleId, t.TrackCode, t.IsSet, t.SortOrder
    FROM sel.Cycle c CROSS APPLY sel.fn_CycleConfiguredTracks(c.CycleId) t
    ORDER BY c.CycleId, t.SortOrder;
END
GO
PRINT '  sel.usp_Cycle_List                applied';
GO

/* sel.usp_Cycle_Spine — the stage strip per process, and the one stage the cycle is
   waiting on.  The primary action on the Cycles screen is computed from this, in SQL. */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_Spine
    @LoginName nvarchar(128),
    @CycleId   int = NULL,
    @AsOf      date = NULL,
    @TestMode  bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT p.CycleId, p.CycleProcessId, p.ProcessTypeCode, pt.Name AS ProcessTypeName,
           p.Name AS ProcessName, p.StartDate AS ProcessStart, p.EndDate AS ProcessEnd, p.SortOrder AS ProcessSort,
           s.CycleStageId, s.StageKindCode, sk.Name AS StageKindName, sk.RouteKey, sk.ScreenCode,
           s.Name AS StageName, s.StartDate, s.EndDate, s.SortOrder AS StageSort,
           s.PerformerLevelValueId, pv.Name AS PerformerLevelName,
           StageState = sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode),
           /* Done / active / pending, for the strip. */
           StripState = CASE sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode)
                             WHEN N'CLOSED' THEN N'done'
                             WHEN N'OPEN'   THEN N'active'
                             ELSE N'pending' END,
           DecisionCount = (SELECT COUNT(DISTINCT d.PersonnelNo) FROM sel.CandidateDecision d
                            JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = d.OrgCode
                            WHERE d.CycleStageId = s.CycleStageId)
    FROM sel.CycleProcess p
    JOIN sel.ProcessType pt ON pt.ProcessTypeCode = p.ProcessTypeCode
    LEFT JOIN sel.CycleStage s ON s.CycleProcessId = p.CycleProcessId
    LEFT JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = s.PerformerLevelValueId
    WHERE (@CycleId IS NULL OR p.CycleId = @CycleId)
    ORDER BY p.CycleId, p.SortOrder, s.SortOrder;

    /* The one stage each cycle is waiting on: the open one, else the next to open. */
    SELECT c.CycleId,
           WaitingStageId = x.CycleStageId,
           WaitingStageName = x.Name,
           WaitingRouteKey = x.RouteKey,
           WaitingState = x.StageState
    FROM sel.Cycle c
    OUTER APPLY (
        SELECT TOP (1) s.CycleStageId, s.Name, sk.RouteKey,
               StageState = sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode)
        FROM sel.CycleStage s
        JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
        JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
        WHERE p.CycleId = c.CycleId
        ORDER BY CASE sel.fn_StageState(s.CycleStageId, @AsOf, @TestMode)
                      WHEN N'OPEN' THEN 0 WHEN N'FUTURE' THEN 1
                      WHEN N'UNDATED' THEN 2 ELSE 3 END,
                 p.SortOrder, s.SortOrder
    ) x
    WHERE (@CycleId IS NULL OR c.CycleId = @CycleId);
END
GO
PRINT '  sel.usp_Cycle_Spine               applied';
GO

/* sel.usp_Cycle_Detail — everything one wizard step needs about a design. */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_Detail
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    /* 1 — the cycle. */
    SELECT c.CycleId, c.CycleCode, c.Name, c.StartDate, c.EndDate, c.OwnerLogin, c.DelegateLogin,
           c.Notes, c.IncumbentSuffix, c.SuccessorSuffix, c.ExistingPoolCode, c.ActiveMembersOnly,
           c.RecipeId, c.OpenedOnUtc, c.ClosedOnUtc, c.PoolCount, c.PoolResolvedOnUtc,
           StatusCode = dv.ValueCode, StatusName = dv.Name, StatusRole = dv.SemanticRole,
           OwnerName    = (SELECT TOP (1) u.DisplayName FROM sec.AppUser u WHERE u.LoginName = c.OwnerLogin),
           DelegateName = (SELECT TOP (1) u.DisplayName FROM sec.AppUser u WHERE u.LoginName = c.DelegateLogin),
           CanEdit     = sec.fn_CanEditCycle(@LoginName, c.CycleId),
           EditRefusal = sec.fn_CycleEditRefusal(@LoginName, c.CycleId),
           RecipeCode  = (SELECT r.RecipeCode FROM sel.CycleRecipe r WHERE r.RecipeId = c.RecipeId),
           AsksJobSuffix = ISNULL((SELECT r.AsksJobSuffix FROM sel.CycleRecipe r WHERE r.RecipeId = c.RecipeId), 0)
    FROM sel.Cycle c
    JOIN cfg.DomainValue dv ON dv.DomainValueId = c.StatusValueId
    WHERE c.CycleId = @CycleId;

    /* 2 — the steps, with which are skipped. */
    SELECT w.StepNo, w.StepCode, w.Caption, w.Description, w.IsSkippable, w.SortOrder,
           IsSkipped = CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.CycleSkippedStep k
                                         WHERE k.CycleId = @CycleId AND k.StepNo = w.StepNo)
                            THEN 1 ELSE 0 END)
    FROM sel.WizardStep w WHERE w.IsActive = 1 ORDER BY w.SortOrder, w.StepNo;

    /* 3 — criterion sets and their criteria, read back as phrases. */
    SELECT cs.CriterionSetId, cs.SetLabel, cs.SortOrder,
           cs.SetModeValueId, mv.ValueCode AS SetModeCode, mv.Name AS SetModeName,
           cs.SetJoinValueId, jv.ValueCode AS SetJoinCode, jv.Name AS SetJoinName
    FROM sel.CycleCriterionSet cs
    JOIN cfg.DomainValue mv ON mv.DomainValueId = cs.SetModeValueId
    LEFT JOIN cfg.DomainValue jv ON jv.DomainValueId = cs.SetJoinValueId
    WHERE cs.CycleId = @CycleId ORDER BY cs.SortOrder, cs.SetLabel;

    SELECT c.CriterionId, c.CriterionSetId, c.RosterFieldId, f.FieldName, f.Caption AS FieldCaption,
           f.DataType, f.SourceKind, c.OperatorCode, o.Name AS OperatorName, o.Arity,
           c.Value1, c.Value2, c.SortOrder,
           Phrase = f.Caption + N' ' + o.Name
                  + CASE WHEN o.Arity = 0 THEN N''
                         WHEN o.Arity = 1 THEN N' ' + ISNULL(c.Value1, N'(no value)')
                         ELSE N' ' + ISNULL(c.Value1, N'(no value)') + N' and ' + ISNULL(c.Value2, N'(no value)') END
    FROM sel.CycleCriterion c
    JOIN sel.CycleCriterionSet cs ON cs.CriterionSetId = c.CriterionSetId
    JOIN sel.RosterField f ON f.RosterFieldId = c.RosterFieldId
    JOIN cfg.Operator o ON o.OperatorCode = c.OperatorCode
    WHERE cs.CycleId = @CycleId ORDER BY cs.SortOrder, c.SortOrder;

    /* 4 — assigned frameworks. */
    SELECT cf.CycleFrameworkId, cf.DevFrameworkId, f.FrameworkCode, f.Name, f.VersionNo, f.UsesLevels,
           sv.ValueCode AS StatusCode, sv.Name AS StatusName,
           EventCount = (SELECT COUNT(DISTINCT i.DevEventId) FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = f.DevFrameworkId),
           LevelCount = (SELECT COUNT(DISTINCT i.LevelNo)    FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = f.DevFrameworkId)
    FROM sel.CycleFramework cf
    JOIN sel.DevFramework f ON f.DevFrameworkId = cf.DevFrameworkId
    JOIN cfg.DomainValue sv ON sv.DomainValueId = f.StatusValueId
    WHERE cf.CycleId = @CycleId ORDER BY f.Name;

    /* 5 — readiness levels. */
    SELECT CycleReadinessId, LevelCode, Name, ThresholdPct, SortOrder
    FROM sel.CycleReadiness WHERE CycleId = @CycleId ORDER BY SortOrder;

    /* 6 — processes and stages. */
    SELECT p.CycleProcessId, p.ProcessTypeCode, pt.Name AS ProcessTypeName, pt.AllowsRepeat,
           p.Name, p.StartDate, p.EndDate, p.SortOrder
    FROM sel.CycleProcess p
    JOIN sel.ProcessType pt ON pt.ProcessTypeCode = p.ProcessTypeCode
    WHERE p.CycleId = @CycleId ORDER BY p.SortOrder;

    SELECT s.CycleStageId, s.CycleProcessId, s.StageKindCode, sk.Name AS StageKindName, sk.RouteKey,
           s.Name, s.StartDate, s.EndDate, s.SortOrder,
           s.PerformerLevelValueId, pv.ValueCode AS PerformerCode, pv.Name AS PerformerName,
           StageState = sel.fn_StageState(s.CycleStageId, @AsOf, 0)
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = s.PerformerLevelValueId
    WHERE p.CycleId = @CycleId ORDER BY p.SortOrder, s.SortOrder;
END
GO
PRINT '  sel.usp_Cycle_Detail              applied';
GO

/* sel.usp_CycleRecipe_List — the "What kind of cycle is this?" chooser.  New design
   never opens an empty form.                                                          */
CREATE OR ALTER PROCEDURE sel.usp_CycleRecipe_List
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.RecipeId, r.RecipeCode, r.Name, r.Description, r.AsksJobSuffix, r.IsCopy, r.SortOrder,
           ProcessSummary = STUFF((SELECT N', ' + ISNULL(rp.Name, pt.Name)
                                   FROM sel.CycleRecipeProcess rp
                                   JOIN sel.ProcessType pt ON pt.ProcessTypeCode = rp.ProcessTypeCode
                                   WHERE rp.RecipeId = r.RecipeId ORDER BY rp.SortOrder
                                   FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N''),
           SkipCount = (SELECT COUNT(*) FROM sel.CycleRecipeSkip k WHERE k.RecipeId = r.RecipeId),
           StepCount = (SELECT COUNT(*) FROM sel.WizardStep w WHERE w.IsActive = 1)
    FROM sel.CycleRecipe r WHERE r.IsActive = 1 ORDER BY r.SortOrder;

    /* The cycles this viewer may copy. */
    SELECT c.CycleId, c.CycleCode, c.Name, dv.ValueCode AS StatusCode, c.StartDate, c.EndDate
    FROM sel.Cycle c JOIN cfg.DomainValue dv ON dv.DomainValueId = c.StatusValueId
    WHERE sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') >= 1
    ORDER BY c.StartDate DESC, c.Name;
END
GO
PRINT '  sel.usp_CycleRecipe_List          applied';
GO

/* sel.usp_JobSuffix_List — the incumbent and successor dropdowns, read from the roster
   as a procedure rather than as inline SQL in a controller.                            */
CREATE OR ALTER PROCEDURE sel.usp_JobSuffix_List
    @LoginName nvarchar(128),
    @ChiefOnly bit = 1,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'ROSTER');
    IF @obj IS NULL
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PermJobSuffix;
        RETURN;
    END;

    DECLARE @active nvarchar(400) = ISNULL(cfg.fn_SettingText(N'ROSTER_ACTIVE_VALUES'), N'Y');
    DECLARE @sql nvarchar(max) = N'
        SELECT DISTINCT PermJobSuffix, PermJobSuffixDesc
        FROM ' + @obj + N'
        WHERE ActiveInd IN (' + cfg.fn_EscapeList(@active) + N')'
        + CASE WHEN @ChiefOnly = 1 THEN N' AND PermChiefInd = N''Y''' ELSE N'' END + N'
          AND PermJobSuffix IS NOT NULL
        ORDER BY PermJobSuffix;';

    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @Problem = N'The job suffixes could not be read from the roster: ' + ERROR_MESSAGE();
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PermJobSuffix;
    END CATCH;
END
GO
PRINT '  sel.usp_JobSuffix_List            applied';
GO

/* sel.usp_Directory_Search — the people-directory search behind owner and delegate. */
CREATE OR ALTER PROCEDURE sel.usp_Directory_Search
    @LoginName nvarchar(128),
    @Search    nvarchar(200),
    @Top       int = 20
AS
BEGIN
    SET NOCOUNT ON;
    IF @Top IS NULL OR @Top < 1 SET @Top = 20;

    SELECT TOP (@Top) u.LoginName, u.DisplayName, u.Email, u.PersonnelNo,
           RoleName = (SELECT TOP (1) r.Name FROM sec.UserRole ur
                       JOIN sec.Role r ON r.RoleId = ur.RoleId
                       WHERE ur.AppUserId = u.AppUserId ORDER BY r.SortOrder)
    FROM sec.AppUser u
    WHERE u.IsActive = 1
      AND (@Search IS NULL OR u.DisplayName LIKE N'%' + @Search + N'%'
                           OR u.LoginName LIKE N'%' + @Search + N'%')
    ORDER BY u.DisplayName;
END
GO
PRINT '  sel.usp_Directory_Search          applied';
GO

/* =====================================================================================
   The cycle aggregate
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_Cycle_Save
    @LoginName      nvarchar(128),
    @CycleId        int = NULL,               -- NULL creates
    @CycleCode      nvarchar(40),
    @Name           nvarchar(300),
    @StartDate      date = NULL,
    @EndDate        date = NULL,
    @OwnerLogin     nvarchar(128) = NULL,
    @DelegateLogin  nvarchar(128) = NULL,
    @Notes          nvarchar(max) = NULL,
    @IncumbentSuffix nvarchar(30) = NULL,
    @SuccessorSuffix nvarchar(30) = NULL,
    @ExistingPoolCode nvarchar(60) = NULL,
    @ActiveMembersOnly bit = 1,
    @RecipeId       int = NULL,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    /* 1 — authority. */
    IF @CycleId IS NULL
    BEGIN
        IF sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') < 2
        BEGIN
            SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
            SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
        END;
    END
    ELSE IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;

    /* 2 — validate. */
    IF NULLIF(LTRIM(RTRIM(@CycleCode)), N'') IS NULL
    BEGIN
        SET @Problem = N'A cycle needs a code.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleCode = @CycleCode AND (@CycleId IS NULL OR CycleId <> @CycleId))
    BEGIN
        SET @Problem = N'There is already a cycle with the code ' + @CycleCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;
    IF @StartDate IS NOT NULL AND @EndDate IS NOT NULL AND @EndDate < @StartDate
    BEGIN
        SET @Problem = N'The end date is before the start date.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;
    IF @DelegateLogin IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sec.AppUser WHERE LoginName = @DelegateLogin)
    BEGIN
        SET @Problem = N'That delegate is not a registered user, so they could not open the design.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;

    DECLARE @before nvarchar(max) = NULL, @after nvarchar(max), @newId int = @CycleId, @action nvarchar(20);
    DECLARE @hadWindow bit = 0;

    BEGIN TRAN;

    IF @CycleId IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.Cycle (CycleCode, Name, StartDate, EndDate, StatusValueId, OwnerLogin, DelegateLogin,
                          Notes, IncumbentSuffix, SuccessorSuffix, ExistingPoolCode, ActiveMembersOnly,
                          RecipeId, CreatedByLogin)
        VALUES (@CycleCode, @Name, @StartDate, @EndDate,
                cfg.fn_DomainValueId(N'CYCLE_STATUS', N'DRAFT'),
                ISNULL(@OwnerLogin, @LoginName), @DelegateLogin, @Notes,
                @IncumbentSuffix, @SuccessorSuffix, @ExistingPoolCode, @ActiveMembersOnly,
                @RecipeId, @LoginName);
        SET @newId = SCOPE_IDENTITY();

        /* A recipe inserts its processes and marks its unneeded steps skipped, so a
           common cycle opens in three steps instead of six. */
        IF @RecipeId IS NOT NULL
        BEGIN
            INSERT sel.CycleProcess (CycleId, ProcessTypeCode, Name, SortOrder)
            SELECT @newId, rp.ProcessTypeCode, ISNULL(rp.Name, pt.Name), rp.SortOrder
            FROM sel.CycleRecipeProcess rp
            JOIN sel.ProcessType pt ON pt.ProcessTypeCode = rp.ProcessTypeCode
            WHERE rp.RecipeId = @RecipeId;

            /* Each process gets the default stages of its type. */
            INSERT sel.CycleStage (CycleProcessId, StageKindCode, Name, SortOrder)
            SELECT p.CycleProcessId, sk.StageKindCode, sk.Name, sk.SortOrder
            FROM sel.CycleProcess p
            JOIN sel.StageKind sk ON sk.ProcessTypeCode = p.ProcessTypeCode AND sk.IsActive = 1
            WHERE p.CycleId = @newId;

            INSERT sel.CycleSkippedStep (CycleId, StepNo, SkippedByLogin)
            SELECT @newId, k.StepNo, @LoginName FROM sel.CycleRecipeSkip k WHERE k.RecipeId = @RecipeId;

            /* The preset readiness ladder, so step 4 is not an empty form either. */
            INSERT sel.CycleReadiness (CycleId, LevelCode, Name, ThresholdPct, SortOrder)
            SELECT @newId, LevelCode, Name, ThresholdPct, SortOrder
            FROM sel.ReadinessLevel WHERE IsActive = 1;
        END;
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT CycleCode, Name, StartDate, EndDate, OwnerLogin, DelegateLogin,
                              IncumbentSuffix, SuccessorSuffix, ExistingPoolCode, ActiveMembersOnly
                       FROM sel.Cycle WHERE CycleId = @CycleId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        SELECT @hadWindow = CASE WHEN StartDate IS NOT NULL AND EndDate IS NOT NULL THEN 1 ELSE 0 END
        FROM sel.Cycle WHERE CycleId = @CycleId;

        UPDATE sel.Cycle
           SET CycleCode = @CycleCode, Name = @Name, StartDate = @StartDate, EndDate = @EndDate,
               OwnerLogin = ISNULL(@OwnerLogin, OwnerLogin), DelegateLogin = @DelegateLogin,
               Notes = @Notes, IncumbentSuffix = @IncumbentSuffix, SuccessorSuffix = @SuccessorSuffix,
               ExistingPoolCode = @ExistingPoolCode, ActiveMembersOnly = @ActiveMembersOnly
        WHERE CycleId = @CycleId;
    END;

    /* The job suffixes, kept in step with the two columns. */
    DELETE FROM sel.CycleJobSuffix WHERE CycleId = @newId;
    IF @IncumbentSuffix IS NOT NULL
        INSERT sel.CycleJobSuffix (CycleId, RoleCode, JobSuffix) VALUES (@newId, N'INCUMBENT', @IncumbentSuffix);
    IF @SuccessorSuffix IS NOT NULL
        INSERT sel.CycleJobSuffix (CycleId, RoleCode, JobSuffix) VALUES (@newId, N'SUCCESSOR', @SuccessorSuffix);

    COMMIT;

    SET @after = (SELECT CycleCode, Name, StartDate, EndDate, OwnerLogin, DelegateLogin,
                         IncumbentSuffix, SuccessorSuffix, ExistingPoolCode, ActiveMembersOnly
                  FROM sel.Cycle WHERE CycleId = @newId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @newId);
    EXEC audit.usp_Log @TableName = N'sel.Cycle', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    /* Setting both dates schedules every undated process and stage.  A hand-set window
       is never overwritten, so this is safe to call every time. */
    IF @StartDate IS NOT NULL AND @EndDate IS NOT NULL
    BEGIN
        DECLARE @p nvarchar(400);
        EXEC sel.usp_Cycle_AutoSchedule @LoginName = @LoginName, @CycleId = @newId, @Problem = @p OUTPUT;
    END;

    SELECT CycleId = @newId, CycleCode = @CycleCode, Name = @Name, WasCreated = CASE WHEN @action = N'INSERT' THEN 1 ELSE 0 END;
END
GO
PRINT '  sel.usp_Cycle_Save                applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Cycle_Delete
    @LoginName nvarchar(128),
    @CycleId   int,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;

    /* Only a draft is deleted.  An active cycle is cancelled, and a closed one is left
       alone — its decisions are the record of what was decided. */
    IF sel.fn_CycleStatusCode(@CycleId) <> N'DRAFT'
    BEGIN
        SET @Problem = N'Only a draft can be deleted. An active cycle is cancelled instead, and a closed one is kept.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT CycleCode, Name FROM sel.Cycle WHERE CycleId = @CycleId
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRAN;
    DELETE FROM sel.CycleCandidateTrace WHERE CycleId = @CycleId;
    DELETE FROM sel.CandidateDecision   WHERE CycleId = @CycleId;
    DELETE pc FROM sel.ProcessCandidate pc JOIN sel.CycleProcess p ON p.CycleProcessId = pc.CycleProcessId WHERE p.CycleId = @CycleId;
    DELETE FROM sel.CycleCandidate      WHERE CycleId = @CycleId;
    DELETE s FROM sel.CycleStage s JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId WHERE p.CycleId = @CycleId;
    DELETE FROM sel.CycleProcess        WHERE CycleId = @CycleId;
    DELETE c FROM sel.CycleCriterion c JOIN sel.CycleCriterionSet cs ON cs.CriterionSetId = c.CriterionSetId WHERE cs.CycleId = @CycleId;
    DELETE FROM sel.CycleCriterionSet   WHERE CycleId = @CycleId;
    DELETE FROM sel.CycleFramework      WHERE CycleId = @CycleId;
    DELETE FROM sel.CycleReadiness      WHERE CycleId = @CycleId;
    DELETE FROM sel.CycleRequirement    WHERE CycleId = @CycleId;
    DELETE FROM sel.CycleSkippedStep    WHERE CycleId = @CycleId;
    DELETE FROM sel.CycleJobSuffix      WHERE CycleId = @CycleId;
    DELETE FROM sel.Cycle               WHERE CycleId = @CycleId;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId);
    EXEC audit.usp_Log @TableName = N'sel.Cycle', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;

    SELECT CycleId = @CycleId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Cycle_Delete              applied';
GO

/* Cancel: an active cycle stops without losing what it decided. */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_Cancel
    @LoginName nvarchar(128),
    @CycleId   int,
    @Reason    nvarchar(600) = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;

    UPDATE sel.Cycle
       SET StatusValueId = cfg.fn_DomainValueId(N'CYCLE_STATUS', N'CANCELLED'),
           ClosedOnUtc = SYSUTCDATETIME(),
           Notes = ISNULL(Notes + NCHAR(10), N'') + N'Cancelled: ' + ISNULL(@Reason, N'(no reason given)')
    WHERE CycleId = @CycleId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId);
    EXEC audit.usp_Log @TableName = N'sel.Cycle', @KeyText = @keyText, @ActionCode = N'CANCEL',
                       @AfterJson = @Reason, @LoginName = @LoginName;

    SELECT CycleId = @CycleId, Cancelled = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Cycle_Cancel              applied';
GO

/* =====================================================================================
   Criteria
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_CriterionSet_Save
    @LoginName   nvarchar(128),
    @CycleId     int,
    @CriterionSetId int = NULL,
    @SetLabel    nvarchar(10) = NULL,
    @SetModeCode nvarchar(60),
    @SetJoinCode nvarchar(60) = NULL,
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CriterionSetId; RETURN;
    END;

    /* Validate against the configuration tables, not literals. */
    DECLARE @modeId int = cfg.fn_DomainValueId(N'SET_MODE', @SetModeCode);
    IF @modeId IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@SetModeCode, N'') + N'" is not a way conditions can be combined.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionSetId; RETURN;
    END;

    DECLARE @joinId int = NULL;
    IF @SetJoinCode IS NOT NULL
    BEGIN
        SET @joinId = cfg.fn_DomainValueId(N'CRITERIA_JOIN', @SetJoinCode);
        IF @joinId IS NULL
        BEGIN
            SET @Problem = N'"' + @SetJoinCode + N'" is not a way one set can join another.';
            SELECT TOP (0) CAST(NULL AS int) AS CriterionSetId; RETURN;
        END;
    END;

    DECLARE @id int = @CriterionSetId, @action nvarchar(20), @before nvarchar(max) = NULL;

    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        /* The next label in the A, B, C... sequence. */
        IF @SetLabel IS NULL
            SELECT @SetLabel = CHAR(65 + ISNULL(COUNT(*), 0)) FROM sel.CycleCriterionSet WHERE CycleId = @CycleId;
        /* The first set has no join; every set after it needs one. */
        IF @joinId IS NULL AND EXISTS (SELECT 1 FROM sel.CycleCriterionSet WHERE CycleId = @CycleId)
            SET @joinId = cfg.fn_DomainValueId(N'CRITERIA_JOIN', N'INTERSECT');

        INSERT sel.CycleCriterionSet (CycleId, SetLabel, SetModeValueId, SetJoinValueId, SortOrder)
        VALUES (@CycleId, @SetLabel, @modeId, @joinId,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleCriterionSet WHERE CycleId = @CycleId), 10));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT SetLabel, SetModeValueId, SetJoinValueId FROM sel.CycleCriterionSet
                       WHERE CriterionSetId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE sel.CycleCriterionSet
           SET SetModeValueId = @modeId,
               SetJoinValueId = @joinId,
               SetLabel = ISNULL(@SetLabel, SetLabel)
        WHERE CriterionSetId = @id;
    END;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    DECLARE @after nvarchar(max) = (SELECT SetLabel, SetModeValueId, SetJoinValueId FROM sel.CycleCriterionSet
                                    WHERE CriterionSetId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.CycleCriterionSet', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT CriterionSetId = @id, SetLabel = (SELECT SetLabel FROM sel.CycleCriterionSet WHERE CriterionSetId = @id);
END
GO
PRINT '  sel.usp_CriterionSet_Save         applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CriterionSet_Delete
    @LoginName      nvarchar(128),
    @CriterionSetId int,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT CycleId FROM sel.CycleCriterionSet WHERE CriterionSetId = @CriterionSetId);
    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That criterion set no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionSetId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CriterionSetId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT SetLabel, SetModeValueId FROM sel.CycleCriterionSet
                                     WHERE CriterionSetId = @CriterionSetId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRAN;
    DELETE FROM sel.CycleCriterion    WHERE CriterionSetId = @CriterionSetId;
    DELETE FROM sel.CycleCriterionSet WHERE CriterionSetId = @CriterionSetId;
    /* The first remaining set has no join. */
    UPDATE sel.CycleCriterionSet SET SetJoinValueId = NULL
    WHERE CriterionSetId = (SELECT TOP (1) CriterionSetId FROM sel.CycleCriterionSet
                            WHERE CycleId = @cycleId ORDER BY SortOrder, SetLabel);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CriterionSetId);
    EXEC audit.usp_Log @TableName = N'sel.CycleCriterionSet', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;

    SELECT CriterionSetId = @CriterionSetId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CriterionSet_Delete       applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Criterion_Save
    @LoginName      nvarchar(128),
    @CriterionSetId int,
    @CriterionId    int = NULL,
    @RosterFieldId  int,
    @OperatorCode   nvarchar(30),
    @Value1         nvarchar(400) = NULL,
    @Value2         nvarchar(400) = NULL,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT CycleId FROM sel.CycleCriterionSet WHERE CriterionSetId = @CriterionSetId);
    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That criterion set no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;

    /* The field must be an enabled, non-sensitive roster field. */
    DECLARE @fieldName nvarchar(128), @dataType nvarchar(20), @enabled bit, @sensitive bit, @present bit;
    SELECT @fieldName = FieldName, @dataType = DataType, @enabled = IsEnabled,
           @sensitive = IsSensitive, @present = IsPresent
    FROM sel.RosterField WHERE RosterFieldId = @RosterFieldId;

    IF @fieldName IS NULL
    BEGIN
        SET @Problem = N'That field is not one of the roster fields.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF @sensitive = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'SENSITIVE_FILTER');
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF @enabled = 0
    BEGIN
        SET @Problem = N'"' + @fieldName + N'" has not been approved for use in criteria. Approve it on the Roster fields screen first.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF @present = 0
    BEGIN
        SET @Problem = N'"' + @fieldName + N'" is no longer in the roster, so it cannot be filtered on.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;

    /* The operator must exist, apply to this data type, and get exactly Arity values. */
    DECLARE @arity tinyint, @appliesTo nvarchar(120), @opName nvarchar(60);
    SELECT @arity = Arity, @appliesTo = AppliesTo, @opName = Name
    FROM cfg.Operator WHERE OperatorCode = @OperatorCode AND IsActive = 1;

    IF @arity IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@OperatorCode, N'') + N'" is not a comparison this application knows.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF N',' + @appliesTo + N',' NOT LIKE N'%,' + @dataType + N',%'
    BEGIN
        SET @Problem = N'"' + @opName + N'" cannot be used on ' + @fieldName + N', which holds ' + @dataType + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF (@arity >= 1 AND NULLIF(LTRIM(RTRIM(ISNULL(@Value1, N''))), N'') IS NULL)
    OR (@arity >= 2 AND NULLIF(LTRIM(RTRIM(ISNULL(@Value2, N''))), N'') IS NULL)
    BEGIN
        SET @Problem = N'"' + @opName + N'" needs ' + CONVERT(nvarchar(2), @arity)
                     + N' value' + CASE WHEN @arity = 1 THEN N'' ELSE N's' END + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    /* An operator with no values must not carry stale ones. */
    IF @arity = 0 BEGIN SET @Value1 = NULL; SET @Value2 = NULL; END;
    IF @arity = 1 SET @Value2 = NULL;

    DECLARE @id int = @CriterionId, @action nvarchar(20), @before nvarchar(max) = NULL;

    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.CycleCriterion (CriterionSetId, RosterFieldId, OperatorCode, Value1, Value2, SortOrder)
        VALUES (@CriterionSetId, @RosterFieldId, @OperatorCode, @Value1, @Value2,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleCriterion WHERE CriterionSetId = @CriterionSetId), 10));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT RosterFieldId, OperatorCode, Value1, Value2 FROM sel.CycleCriterion
                       WHERE CriterionId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE sel.CycleCriterion
           SET RosterFieldId = @RosterFieldId, OperatorCode = @OperatorCode,
               Value1 = @Value1, Value2 = @Value2
        WHERE CriterionId = @id;
    END;

    UPDATE sel.RosterField SET UsageCount = UsageCount + 1 WHERE RosterFieldId = @RosterFieldId AND @action = N'INSERT';
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    DECLARE @after nvarchar(max) = (SELECT RosterFieldId, OperatorCode, Value1, Value2 FROM sel.CycleCriterion
                                    WHERE CriterionId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.CycleCriterion', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT CriterionId = @id, Phrase = @fieldName + N' ' + @opName
         + CASE WHEN @arity = 0 THEN N'' WHEN @arity = 1 THEN N' ' + @Value1
                ELSE N' ' + @Value1 + N' and ' + @Value2 END;
END
GO
PRINT '  sel.usp_Criterion_Save            applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Criterion_Delete
    @LoginName   nvarchar(128),
    @CriterionId int,
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT cs.CycleId FROM sel.CycleCriterion c
                            JOIN sel.CycleCriterionSet cs ON cs.CriterionSetId = c.CriterionSetId
                            WHERE c.CriterionId = @CriterionId);
    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That criterion no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CriterionId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT RosterFieldId, OperatorCode, Value1, Value2
                                     FROM sel.CycleCriterion WHERE CriterionId = @CriterionId
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM sel.CycleCriterion WHERE CriterionId = @CriterionId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CriterionId);
    EXEC audit.usp_Log @TableName = N'sel.CycleCriterion', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;

    SELECT CriterionId = @CriterionId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Criterion_Delete          applied';
GO

/* =====================================================================================
   Frameworks assigned to a cycle, readiness levels, requirements
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_CycleFramework_Assign
    @LoginName      nvarchar(128),
    @CycleId        int,
    @DevFrameworkId int,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleFrameworkId; RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM sel.DevFramework WHERE DevFrameworkId = @DevFrameworkId)
    BEGIN
        SET @Problem = N'That framework no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleFrameworkId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.CycleFramework WHERE CycleId = @CycleId AND DevFrameworkId = @DevFrameworkId)
    BEGIN
        SET @Problem = N'That framework is already assigned to this cycle.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleFrameworkId; RETURN;
    END;

    INSERT sel.CycleFramework (CycleId, DevFrameworkId) VALUES (@CycleId, @DevFrameworkId);
    DECLARE @id int = SCOPE_IDENTITY();

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId) + N'/' + CONVERT(nvarchar(20), @DevFrameworkId);
    EXEC audit.usp_Log @TableName = N'sel.CycleFramework', @KeyText = @keyText, @ActionCode = N'ASSIGN',
                       @LoginName = @LoginName;

    SELECT CycleFrameworkId = @id, CycleId = @CycleId, DevFrameworkId = @DevFrameworkId;
END
GO
PRINT '  sel.usp_CycleFramework_Assign     applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleFramework_Remove
    @LoginName      nvarchar(128),
    @CycleId        int,
    @DevFrameworkId int,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleId; RETURN;
    END;

    DELETE FROM sel.CycleFramework WHERE CycleId = @CycleId AND DevFrameworkId = @DevFrameworkId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId) + N'/' + CONVERT(nvarchar(20), @DevFrameworkId);
    EXEC audit.usp_Log @TableName = N'sel.CycleFramework', @KeyText = @keyText, @ActionCode = N'REMOVE',
                       @LoginName = @LoginName;

    SELECT CycleId = @CycleId, DevFrameworkId = @DevFrameworkId, Removed = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CycleFramework_Remove     applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleReadiness_Save
    @LoginName        nvarchar(128),
    @CycleId          int,
    @CycleReadinessId int = NULL,
    @LevelCode        nvarchar(20),
    @Name             nvarchar(120),
    @ThresholdPct     decimal(9,4) = NULL,
    @SortOrder        int = NULL,
    @Problem          nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@LevelCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@Name)), N'') IS NULL
    BEGIN
        SET @Problem = N'A readiness level needs both a code and a name.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.CycleReadiness WHERE CycleId = @CycleId AND LevelCode = @LevelCode
                 AND (@CycleReadinessId IS NULL OR CycleReadinessId <> @CycleReadinessId))
    BEGIN
        SET @Problem = N'This cycle already has a level called ' + @LevelCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;
    IF @ThresholdPct IS NOT NULL AND EXISTS (SELECT 1 FROM sel.CycleReadiness
        WHERE CycleId = @CycleId AND ThresholdPct = @ThresholdPct
          AND (@CycleReadinessId IS NULL OR CycleReadinessId <> @CycleReadinessId))
    BEGIN
        SET @Problem = N'Another level already sits at ' + CONVERT(nvarchar(20), CAST(@ThresholdPct AS decimal(9,1)))
                     + N'%, so nobody could ever be placed at both.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;
    IF @ThresholdPct IS NOT NULL AND (@ThresholdPct < 0 OR @ThresholdPct > 100)
    BEGIN
        SET @Problem = N'A threshold is a percentage, so it sits between 0 and 100.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;

    DECLARE @id int = @CycleReadinessId, @action nvarchar(20), @before nvarchar(max) = NULL;

    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.CycleReadiness (CycleId, LevelCode, Name, ThresholdPct, SortOrder)
        VALUES (@CycleId, @LevelCode, @Name, @ThresholdPct,
                ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleReadiness WHERE CycleId = @CycleId), 10)));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT LevelCode, Name, ThresholdPct, SortOrder FROM sel.CycleReadiness
                       WHERE CycleReadinessId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE sel.CycleReadiness
           SET LevelCode = @LevelCode, Name = @Name, ThresholdPct = @ThresholdPct,
               SortOrder = ISNULL(@SortOrder, SortOrder)
        WHERE CycleReadinessId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    DECLARE @after nvarchar(max) = (SELECT LevelCode, Name, ThresholdPct, SortOrder FROM sel.CycleReadiness
                                    WHERE CycleReadinessId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.CycleReadiness', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT CycleReadinessId = @id, LevelCode = @LevelCode, Name = @Name, ThresholdPct = @ThresholdPct;
END
GO
PRINT '  sel.usp_CycleReadiness_Save       applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleReadiness_Delete
    @LoginName        nvarchar(128),
    @CycleReadinessId int,
    @Problem          nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT CycleId FROM sel.CycleReadiness WHERE CycleReadinessId = @CycleReadinessId);
    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That level no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleReadinessId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT LevelCode, Name, ThresholdPct FROM sel.CycleReadiness
                                     WHERE CycleReadinessId = @CycleReadinessId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM sel.CycleReadiness WHERE CycleReadinessId = @CycleReadinessId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleReadinessId);
    EXEC audit.usp_Log @TableName = N'sel.CycleReadiness', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;

    SELECT CycleReadinessId = @CycleReadinessId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CycleReadiness_Delete     applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleRequirement_Save
    @LoginName  nvarchar(128),
    @CycleId    int,
    @CycleRequirementId int = NULL,
    @DevEventId int,
    @LevelCode  nvarchar(20) = NULL,
    @Weight     decimal(9,4) = 0,
    @IsMust     bit = 0,
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleRequirementId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.DevEvent WHERE DevEventId = @DevEventId)
    BEGIN
        SET @Problem = N'That development event no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleRequirementId; RETURN;
    END;
    IF @LevelCode IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sel.CycleReadiness WHERE CycleId = @CycleId AND LevelCode = @LevelCode)
    BEGIN
        SET @Problem = N'This cycle has no readiness level called ' + @LevelCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleRequirementId; RETURN;
    END;

    DECLARE @id int = @CycleRequirementId, @action nvarchar(20);
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.CycleRequirement (CycleId, DevEventId, LevelCode, Weight, IsMust, SortOrder)
        VALUES (@CycleId, @DevEventId, @LevelCode, @Weight, @IsMust,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleRequirement WHERE CycleId = @CycleId), 10));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.CycleRequirement SET DevEventId = @DevEventId, LevelCode = @LevelCode,
               Weight = @Weight, IsMust = @IsMust WHERE CycleRequirementId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.CycleRequirement', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;
    SELECT CycleRequirementId = @id;
END
GO
PRINT '  sel.usp_CycleRequirement_Save     applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleRequirement_Delete
    @LoginName          nvarchar(128),
    @CycleRequirementId int,
    @Problem            nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    DECLARE @cycleId int = (SELECT CycleId FROM sel.CycleRequirement WHERE CycleRequirementId = @CycleRequirementId);
    IF @cycleId IS NULL OR sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = ISNULL(sec.fn_CycleEditRefusal(@LoginName, @cycleId), N'That requirement no longer exists.');
        SELECT TOP (0) CAST(NULL AS int) AS CycleRequirementId; RETURN;
    END;
    DELETE FROM sel.CycleRequirement WHERE CycleRequirementId = @CycleRequirementId;
    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleRequirementId);
    EXEC audit.usp_Log @TableName = N'sel.CycleRequirement', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @LoginName = @LoginName;
    SELECT CycleRequirementId = @CycleRequirementId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CycleRequirement_Delete   applied';
GO

/* =====================================================================================
   Processes and stages
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_CycleProcess_Save
    @LoginName       nvarchar(128),
    @CycleId         int,
    @CycleProcessId  int = NULL,
    @ProcessTypeCode nvarchar(30),
    @Name            nvarchar(200) = NULL,
    @StartDate       date = NULL,
    @EndDate         date = NULL,
    @Problem         nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;

    DECLARE @allowsRepeat bit, @typeName nvarchar(120);
    SELECT @allowsRepeat = AllowsRepeat, @typeName = Name
    FROM sel.ProcessType WHERE ProcessTypeCode = @ProcessTypeCode AND IsActive = 1;

    IF @typeName IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@ProcessTypeCode, N'') + N'" is not a kind of process this application runs.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;
    /* AllowsRepeat decides whether one may be added twice — the table decides, not the code. */
    IF @CycleProcessId IS NULL AND @allowsRepeat = 0
       AND EXISTS (SELECT 1 FROM sel.CycleProcess WHERE CycleId = @CycleId AND ProcessTypeCode = @ProcessTypeCode)
    BEGIN
        SET @Problem = N'This cycle already has a ' + LOWER(@typeName) + N' process, and that kind cannot be added twice.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;

    DECLARE @id int = @CycleProcessId, @action nvarchar(20), @isNew bit = 0;

    BEGIN TRAN;
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT'; SET @isNew = 1;
        INSERT sel.CycleProcess (CycleId, ProcessTypeCode, Name, StartDate, EndDate, SortOrder)
        VALUES (@CycleId, @ProcessTypeCode, ISNULL(@Name, @typeName), @StartDate, @EndDate,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleProcess WHERE CycleId = @CycleId), 10));
        SET @id = SCOPE_IDENTITY();

        /* A new process arrives with its type's default stages. */
        INSERT sel.CycleStage (CycleProcessId, StageKindCode, Name, SortOrder)
        SELECT @id, sk.StageKindCode, sk.Name, sk.SortOrder
        FROM sel.StageKind sk WHERE sk.ProcessTypeCode = @ProcessTypeCode AND sk.IsActive = 1
        ORDER BY sk.SortOrder;
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.CycleProcess SET Name = ISNULL(@Name, Name), StartDate = @StartDate, EndDate = @EndDate
        WHERE CycleProcessId = @id;

        /* Moving a process window re-fits its stages. */
        IF @StartDate IS NOT NULL AND @EndDate IS NOT NULL
        BEGIN
            ;WITH s AS
            (
                SELECT CycleStageId,
                       rn = ROW_NUMBER() OVER (ORDER BY SortOrder, CycleStageId),
                       n  = COUNT(*) OVER ()
                FROM sel.CycleStage WHERE CycleProcessId = @id
            )
            UPDATE cs
               SET StartDate = DATEADD(DAY, CAST(DATEDIFF(DAY, @StartDate, @EndDate) * (s.rn - 1.0) / s.n AS int), @StartDate),
                   EndDate   = DATEADD(DAY, CAST(DATEDIFF(DAY, @StartDate, @EndDate) * (s.rn * 1.0)  / s.n AS int) - 1, @StartDate)
            FROM sel.CycleStage cs JOIN s ON s.CycleStageId = cs.CycleStageId;
        END;
    END;
    COMMIT;

    /* Adding a process splits the cycle window evenly across its stages. */
    IF @isNew = 1
    BEGIN
        DECLARE @p nvarchar(400);
        EXEC sel.usp_Cycle_AutoSchedule @LoginName = @LoginName, @CycleId = @CycleId, @Problem = @p OUTPUT;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.CycleProcess', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;

    SELECT CycleProcessId = @id, CycleId = @CycleId, ProcessTypeCode = @ProcessTypeCode;
END
GO
PRINT '  sel.usp_CycleProcess_Save         applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleProcess_Duplicate
    @LoginName      nvarchar(128),
    @CycleProcessId int,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int, @typeCode nvarchar(30), @name nvarchar(200), @allowsRepeat bit;
    SELECT @cycleId = p.CycleId, @typeCode = p.ProcessTypeCode, @name = p.Name, @allowsRepeat = pt.AllowsRepeat
    FROM sel.CycleProcess p JOIN sel.ProcessType pt ON pt.ProcessTypeCode = p.ProcessTypeCode
    WHERE p.CycleProcessId = @CycleProcessId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That process no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;
    IF @allowsRepeat = 0
    BEGIN
        SET @Problem = N'A ' + LOWER(@name) + N' process cannot be added twice.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;

    BEGIN TRAN;
    INSERT sel.CycleProcess (CycleId, ProcessTypeCode, Name, SortOrder)
    VALUES (@cycleId, @typeCode, @name + N' (copy)',
            ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleProcess WHERE CycleId = @cycleId), 10));
    DECLARE @newId int = SCOPE_IDENTITY();

    INSERT sel.CycleStage (CycleProcessId, StageKindCode, Name, PerformerLevelValueId, SortOrder)
    SELECT @newId, StageKindCode, Name, PerformerLevelValueId, SortOrder
    FROM sel.CycleStage WHERE CycleProcessId = @CycleProcessId;
    COMMIT;

    DECLARE @p nvarchar(400);
    EXEC sel.usp_Cycle_AutoSchedule @LoginName = @LoginName, @CycleId = @cycleId, @Problem = @p OUTPUT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @newId);
    EXEC audit.usp_Log @TableName = N'sel.CycleProcess', @KeyText = @keyText, @ActionCode = N'DUPLICATE',
                       @LoginName = @LoginName;

    SELECT CycleProcessId = @newId, CycleId = @cycleId;
END
GO
PRINT '  sel.usp_CycleProcess_Duplicate    applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleProcess_Remove
    @LoginName      nvarchar(128),
    @CycleProcessId int,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT CycleId FROM sel.CycleProcess WHERE CycleProcessId = @CycleProcessId);
    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That process no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;

    /* Decisions are the record of what people decided.  Removing a process that already
       carries them would delete that record, so it is refused rather than cascaded. */
    IF EXISTS (SELECT 1 FROM sel.CandidateDecision WHERE CycleProcessId = @CycleProcessId)
    BEGIN
        SET @Problem = N'Decisions have already been taken in this process, so it cannot be removed.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId; RETURN;
    END;

    BEGIN TRAN;
    DELETE FROM sel.ProcessCandidate WHERE CycleProcessId = @CycleProcessId;
    DELETE FROM sel.CycleStage       WHERE CycleProcessId = @CycleProcessId;
    DELETE FROM sel.CycleProcess     WHERE CycleProcessId = @CycleProcessId;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleProcessId);
    EXEC audit.usp_Log @TableName = N'sel.CycleProcess', @KeyText = @keyText, @ActionCode = N'REMOVE',
                       @LoginName = @LoginName;

    SELECT CycleProcessId = @CycleProcessId, Removed = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CycleProcess_Remove       applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleStage_Save
    @LoginName      nvarchar(128),
    @CycleProcessId int,
    @CycleStageId   int = NULL,
    @StageKindCode  nvarchar(30) = NULL,
    @Name           nvarchar(200) = NULL,
    @StartDate      date = NULL,
    @EndDate        date = NULL,
    @PerformerCode  nvarchar(60) = NULL,
    @SortOrder      int = NULL,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int, @cyStart date, @cyEnd date;
    SELECT @cycleId = p.CycleId, @cyStart = c.StartDate, @cyEnd = c.EndDate
    FROM sel.CycleProcess p JOIN sel.Cycle c ON c.CycleId = p.CycleId
    WHERE p.CycleProcessId = @CycleProcessId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That process no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
    END;
    IF sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @cycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
    END;

    IF @StartDate IS NOT NULL AND @EndDate IS NOT NULL AND @EndDate < @StartDate
    BEGIN
        SET @Problem = N'This stage ends before it starts.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
    END;
    IF @StartDate IS NOT NULL AND @cyStart IS NOT NULL AND (@StartDate < @cyStart OR @EndDate > @cyEnd)
    BEGIN
        SET @Problem = N'A stage has to sit inside the cycle window, which runs '
                     + CONVERT(nvarchar(10), @cyStart, 23) + N' to ' + CONVERT(nvarchar(10), @cyEnd, 23) + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
    END;

    /* Who performs it must be a live management level. */
    DECLARE @performerId int = NULL;
    IF @PerformerCode IS NOT NULL
    BEGIN
        SET @performerId = cfg.fn_DomainValueId(N'MANAGEMENT_LEVEL', @PerformerCode);
        IF @performerId IS NULL
        BEGIN
            SET @Problem = N'"' + @PerformerCode + N'" is not one of the management levels that can perform a stage.';
            SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
        END;
    END;

    DECLARE @id int = @CycleStageId, @action nvarchar(20), @before nvarchar(max) = NULL;
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        IF @StageKindCode IS NULL
            SELECT TOP (1) @StageKindCode = sk.StageKindCode FROM sel.StageKind sk
            JOIN sel.CycleProcess p ON p.ProcessTypeCode = sk.ProcessTypeCode
            WHERE p.CycleProcessId = @CycleProcessId ORDER BY sk.SortOrder;

        INSERT sel.CycleStage (CycleProcessId, StageKindCode, Name, StartDate, EndDate, PerformerLevelValueId, SortOrder)
        VALUES (@CycleProcessId, @StageKindCode,
                ISNULL(@Name, (SELECT Name FROM sel.StageKind WHERE StageKindCode = @StageKindCode)),
                @StartDate, @EndDate, @performerId,
                ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.CycleStage WHERE CycleProcessId = @CycleProcessId), 10)));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT Name, StartDate, EndDate, PerformerLevelValueId, SortOrder
                       FROM sel.CycleStage WHERE CycleStageId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE sel.CycleStage
           SET Name = ISNULL(@Name, Name), StartDate = @StartDate, EndDate = @EndDate,
               PerformerLevelValueId = ISNULL(@performerId, PerformerLevelValueId),
               SortOrder = ISNULL(@SortOrder, SortOrder)
        WHERE CycleStageId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    DECLARE @after nvarchar(max) = (SELECT Name, StartDate, EndDate, PerformerLevelValueId, SortOrder
                                    FROM sel.CycleStage WHERE CycleStageId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.CycleStage', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT CycleStageId = @id, CycleProcessId = @CycleProcessId;
END
GO
PRINT '  sel.usp_CycleStage_Save           applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleStage_Delete
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);
    IF @cycleId IS NULL OR sec.fn_CanEditCycle(@LoginName, @cycleId) = 0
    BEGIN
        SET @Problem = ISNULL(sec.fn_CycleEditRefusal(@LoginName, @cycleId), N'That stage no longer exists.');
        SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.CandidateDecision WHERE CycleStageId = @CycleStageId)
    BEGIN
        SET @Problem = N'Decisions have already been taken in this stage, so it cannot be removed.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleStageId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT Name, StartDate, EndDate FROM sel.CycleStage
                                     WHERE CycleStageId = @CycleStageId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM sel.CycleStage WHERE CycleStageId = @CycleStageId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleStageId);
    EXEC audit.usp_Log @TableName = N'sel.CycleStage', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;

    SELECT CycleStageId = @CycleStageId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CycleStage_Delete         applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CycleSkippedStep_Set
    @LoginName nvarchar(128),
    @CycleId   int,
    @StepNo    int,
    @IsSkipped bit,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS StepNo; RETURN;
    END;

    DECLARE @skippable bit, @caption nvarchar(120);
    SELECT @skippable = IsSkippable, @caption = Caption FROM sel.WizardStep WHERE StepNo = @StepNo;
    IF @caption IS NULL
    BEGIN
        SET @Problem = N'There is no step ' + CONVERT(nvarchar(10), @StepNo) + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS StepNo; RETURN;
    END;
    IF @IsSkipped = 1 AND @skippable = 0
    BEGIN
        SET @Problem = N'"' + @caption + N'" cannot be skipped.';
        SELECT TOP (0) CAST(NULL AS int) AS StepNo; RETURN;
    END;

    IF @IsSkipped = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sel.CycleSkippedStep WHERE CycleId = @CycleId AND StepNo = @StepNo)
            INSERT sel.CycleSkippedStep (CycleId, StepNo, SkippedByLogin) VALUES (@CycleId, @StepNo, @LoginName);
    END
    ELSE
        DELETE FROM sel.CycleSkippedStep WHERE CycleId = @CycleId AND StepNo = @StepNo;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId) + N'/' + CONVERT(nvarchar(10), @StepNo);
    DECLARE @act nvarchar(20) = CASE WHEN @IsSkipped = 1 THEN N'SKIP' ELSE N'UNSKIP' END;
    EXEC audit.usp_Log @TableName = N'sel.CycleSkippedStep', @KeyText = @keyText, @ActionCode = @act,
                       @LoginName = @LoginName;

    SELECT StepNo = @StepNo, IsSkipped = @IsSkipped, Caption = @caption;
END
GO
PRINT '  sel.usp_CycleSkippedStep_Set      applied';
GO


/* =====================================================================================
   10_crud.sql, continued  —  the configuration aggregates
   ===================================================================================== */

PRINT '';
PRINT '== 10_crud (configuration aggregates) ================================';
GO

/* =====================================================================================
   Development events and their completion rules
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_DevEvent_Save
    @LoginName      nvarchar(128),
    @DevEventId     int = NULL,
    @EventCode      nvarchar(60),
    @Name           nvarchar(300),
    @Description    nvarchar(600) = NULL,
    @KindCode       nvarchar(30),
    @ItemCode       nvarchar(60) = NULL,
    @EventTypeCode  nvarchar(60) = NULL,
    @PartCode       nvarchar(60) = NULL,
    @MeasureCode    nvarchar(60) = NULL,
    @PhaseCode      nvarchar(60) = NULL,
    @PassValue      nvarchar(120) = NULL,
    @SumFloor       decimal(18,4) = NULL,
    @ValidityMonths int = NULL,
    @RetiredFrom    date = NULL,
    @IsActive       bit = 1,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    IF NULLIF(LTRIM(RTRIM(@EventCode)), N'') IS NULL
    BEGIN
        SET @Problem = N'An event needs a code.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.DevEvent WHERE EventCode = @EventCode
                 AND (@DevEventId IS NULL OR DevEventId <> @DevEventId))
    BEGIN
        SET @Problem = N'There is already an event with the code ' + @EventCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    /* The kind must exist, because how this event is judged comes from it. */
    DECLARE @evalMode nvarchar(20) = (SELECT EvalModeCode FROM sel.RequirementKind WHERE KindCode = @KindCode AND IsActive = 1);
    IF @evalMode IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@KindCode, N'') + N'" is not a requirement kind this application knows.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;
    /* A summed kind is met against a floor, so it needs one. */
    IF @evalMode = N'SUM' AND @SumFloor IS NULL
    BEGIN
        SET @Problem = N'A summed requirement needs a figure to reach. Set the floor on the rule panel.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    /* Each of these must be a live value of its domain. */
    DECLARE @typeId int = CASE WHEN @EventTypeCode IS NULL THEN NULL ELSE cfg.fn_DomainValueId(N'EVENT_TYPE', @EventTypeCode) END;
    DECLARE @partId int = CASE WHEN @PartCode    IS NULL THEN NULL ELSE cfg.fn_DomainValueId(N'PART',       @PartCode)    END;
    DECLARE @measId int = CASE WHEN @MeasureCode IS NULL THEN NULL ELSE cfg.fn_DomainValueId(N'MEASURE',    @MeasureCode) END;
    DECLARE @phasId int = CASE WHEN @PhaseCode   IS NULL THEN NULL ELSE cfg.fn_DomainValueId(N'PHASE',      @PhaseCode)   END;

    IF (@EventTypeCode IS NOT NULL AND @typeId IS NULL) OR (@PartCode    IS NOT NULL AND @partId IS NULL)
    OR (@MeasureCode   IS NOT NULL AND @measId IS NULL) OR (@PhaseCode   IS NOT NULL AND @phasId IS NULL)
    BEGIN
        SET @Problem = N'One of the type, part, measure or phase is not a value this application knows.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    DECLARE @id int = @DevEventId, @action nvarchar(20), @before nvarchar(max) = NULL;

    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.DevEvent (EventCode, Name, Description, EventTypeValueId, PartValueId, MeasureValueId,
                             PhaseValueId, KindCode, ItemCode, PassValue, SumFloor, ValidityMonths,
                             RetiredFrom, IsActive)
        VALUES (@EventCode, @Name, @Description, @typeId, @partId, @measId, @phasId, @KindCode,
                ISNULL(@ItemCode, @EventCode), @PassValue, @SumFloor, @ValidityMonths, @RetiredFrom, @IsActive);
        SET @id = SCOPE_IDENTITY();

        /* An event that names a code the catalogue has never seen upserts it for review,
           rather than becoming a requirement nothing can ever satisfy. */
        IF NOT EXISTS (SELECT 1 FROM sel.CatalogItem WHERE KindCode = @KindCode AND ItemCode = ISNULL(@ItemCode, @EventCode))
            INSERT sel.CatalogItem (ItemCode, Name, KindCode, NeedsReview)
            VALUES (ISNULL(@ItemCode, @EventCode), @Name, @KindCode, 1);
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT EventCode, Name, KindCode, ItemCode, PassValue, SumFloor, IsActive
                       FROM sel.DevEvent WHERE DevEventId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE sel.DevEvent
           SET EventCode = @EventCode, Name = @Name, Description = @Description,
               EventTypeValueId = @typeId, PartValueId = @partId, MeasureValueId = @measId,
               PhaseValueId = @phasId, KindCode = @KindCode, ItemCode = ISNULL(@ItemCode, @EventCode),
               PassValue = @PassValue, SumFloor = @SumFloor, ValidityMonths = @ValidityMonths,
               RetiredFrom = @RetiredFrom, IsActive = @IsActive
        WHERE DevEventId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    DECLARE @after nvarchar(max) = (SELECT EventCode, Name, KindCode, ItemCode, PassValue, SumFloor, IsActive
                                    FROM sel.DevEvent WHERE DevEventId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.DevEvent', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT DevEventId = @id, EventCode = @EventCode,
           RuleText  = sel.fn_EventRuleText(@id),
           RuleShort = sel.fn_EventRuleShort(@id);
END
GO
PRINT '  sel.usp_DevEvent_Save             applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_DevEvent_Delete
    @LoginName  nvarchar(128),
    @DevEventId int,
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    DECLARE @inUse int = (SELECT COUNT(DISTINCT DevFrameworkId) FROM sel.DevFrameworkItem WHERE DevEventId = @DevEventId);
    IF @inUse > 0
    BEGIN
        SET @Problem = N'This event is used by ' + CONVERT(nvarchar(10), @inUse) + N' framework'
                     + CASE WHEN @inUse = 1 THEN N'' ELSE N's' END
                     + N'. Remove it from those first, or retire it instead.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT EventCode, Name, KindCode FROM sel.DevEvent
                                     WHERE DevEventId = @DevEventId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    BEGIN TRAN;
    DELETE c FROM sel.DevEventCondition c
    JOIN sel.DevEventConditionSet cs ON cs.SetId = c.SetId WHERE cs.DevEventId = @DevEventId;
    DELETE FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId;
    DELETE FROM sel.CycleRequirement     WHERE DevEventId = @DevEventId;
    DELETE FROM sel.DevEvent             WHERE DevEventId = @DevEventId;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevEventId);
    EXEC audit.usp_Log @TableName = N'sel.DevEvent', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;
    SELECT DevEventId = @DevEventId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_DevEvent_Delete           applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_EventConditionSet_Save
    @LoginName   nvarchar(128),
    @DevEventId  int,
    @SetId       int = NULL,
    @SetModeCode nvarchar(60),
    @SetJoinCode nvarchar(60) = NULL,
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS SetId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.DevEvent WHERE DevEventId = @DevEventId)
    BEGIN
        SET @Problem = N'That event no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS SetId; RETURN;
    END;

    DECLARE @modeId int = cfg.fn_DomainValueId(N'SET_MODE', @SetModeCode);
    IF @modeId IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@SetModeCode, N'') + N'" is not a way conditions can be combined.';
        SELECT TOP (0) CAST(NULL AS int) AS SetId; RETURN;
    END;
    DECLARE @joinId int = CASE WHEN @SetJoinCode IS NULL THEN NULL ELSE cfg.fn_DomainValueId(N'SET_JOIN', @SetJoinCode) END;
    IF @SetJoinCode IS NOT NULL AND @joinId IS NULL
    BEGIN
        SET @Problem = N'"' + @SetJoinCode + N'" is not a way one set can join another.';
        SELECT TOP (0) CAST(NULL AS int) AS SetId; RETURN;
    END;

    DECLARE @id int = @SetId, @action nvarchar(20), @label nvarchar(10);
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        SELECT @label = CHAR(65 + ISNULL(COUNT(*), 0)) FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId;
        IF @joinId IS NULL AND EXISTS (SELECT 1 FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId)
            SET @joinId = cfg.fn_DomainValueId(N'SET_JOIN', N'AND');

        INSERT sel.DevEventConditionSet (DevEventId, SetLabel, SetModeValueId, SetJoinValueId, SortOrder)
        VALUES (@DevEventId, @label, @modeId, @joinId,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId), 10));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.DevEventConditionSet SET SetModeValueId = @modeId, SetJoinValueId = @joinId WHERE SetId = @id;
        SELECT @label = SetLabel FROM sel.DevEventConditionSet WHERE SetId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.DevEventConditionSet', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;

    SELECT SetId = @id, SetLabel = @label, RuleText = sel.fn_EventRuleText(@DevEventId);
END
GO
PRINT '  sel.usp_EventConditionSet_Save    applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_EventConditionSet_Delete
    @LoginName nvarchar(128),
    @SetId     int,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS SetId; RETURN;
    END;

    DECLARE @evId int = (SELECT DevEventId FROM sel.DevEventConditionSet WHERE SetId = @SetId);
    IF @evId IS NULL
    BEGIN
        SET @Problem = N'That condition set no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS SetId; RETURN;
    END;

    BEGIN TRAN;
    DELETE FROM sel.DevEventCondition    WHERE SetId = @SetId;
    DELETE FROM sel.DevEventConditionSet WHERE SetId = @SetId;
    /* The first remaining set never carries a join. */
    UPDATE sel.DevEventConditionSet SET SetJoinValueId = NULL
    WHERE SetId = (SELECT TOP (1) SetId FROM sel.DevEventConditionSet
                   WHERE DevEventId = @evId ORDER BY SortOrder, SetLabel);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @SetId);
    EXEC audit.usp_Log @TableName = N'sel.DevEventConditionSet', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @LoginName = @LoginName;

    SELECT SetId = @SetId, Deleted = CAST(1 AS bit), RuleText = sel.fn_EventRuleText(@evId);
END
GO
PRINT '  sel.usp_EventConditionSet_Delete  applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_EventCondition_Save
    @LoginName    nvarchar(128),
    @SetId        int,
    @ConditionId  int = NULL,
    @FieldName    nvarchar(128) = NULL,
    @OperatorCode nvarchar(30) = NULL,
    @Value1       nvarchar(400) = NULL,
    @Value2       nvarchar(400) = NULL,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
    END;

    DECLARE @evId int, @kind nvarchar(30), @sourceId int;
    SELECT @evId = cs.DevEventId FROM sel.DevEventConditionSet cs WHERE cs.SetId = @SetId;
    IF @evId IS NULL
    BEGIN
        SET @Problem = N'That condition set no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
    END;
    SELECT @kind = KindCode FROM sel.DevEvent WHERE DevEventId = @evId;
    SELECT @sourceId = EvidenceSourceId FROM sel.EvidenceSource WHERE KindCode = @kind;

    /* The operator must exist and collect exactly its Arity of values. */
    DECLARE @arity tinyint, @opName nvarchar(60), @appliesTo nvarchar(120);
    IF @OperatorCode IS NOT NULL
    BEGIN
        SELECT @arity = Arity, @opName = Name, @appliesTo = AppliesTo
        FROM cfg.Operator WHERE OperatorCode = @OperatorCode AND IsActive = 1;
        IF @arity IS NULL
        BEGIN
            SET @Problem = N'"' + @OperatorCode + N'" is not a comparison this application knows.';
            SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
        END;
        IF (@arity >= 1 AND NULLIF(LTRIM(RTRIM(ISNULL(@Value1, N''))), N'') IS NULL)
        OR (@arity >= 2 AND NULLIF(LTRIM(RTRIM(ISNULL(@Value2, N''))), N'') IS NULL)
        BEGIN
            SET @Problem = N'"' + @opName + N'" needs ' + CONVERT(nvarchar(2), @arity)
                         + N' value' + CASE WHEN @arity = 1 THEN N'' ELSE N's' END + N'.';
            SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
        END;
        IF @arity = 0 BEGIN SET @Value1 = NULL; SET @Value2 = NULL; END;
        IF @arity = 1 SET @Value2 = NULL;
    END;

    /* A field typed once is learned into this source's column list and offered to every
       event after, so the next author picks from a list instead of guessing a spelling. */
    IF @FieldName IS NOT NULL AND LTRIM(RTRIM(@FieldName)) <> N''
    BEGIN
        DECLARE @lp nvarchar(400);
        EXEC sel.usp_EvidenceSourceColumn_Learn @LoginName = @LoginName, @KindCode = @kind,
             @ColumnName = @FieldName, @Problem = @lp OUTPUT;

        /* The operator must apply to the field's data type — never carry over an operator
           that reads as nonsense ("Status is at least 90"). */
        IF @OperatorCode IS NOT NULL
        BEGIN
            DECLARE @fieldType nvarchar(20) = ISNULL((SELECT DataType FROM sel.EvidenceSourceColumn
                                                      WHERE EvidenceSourceId = @sourceId AND ColumnName = @FieldName), N'text');
            IF N',' + @appliesTo + N',' NOT LIKE N'%,' + @fieldType + N',%'
            BEGIN
                SET @Problem = N'"' + @opName + N'" cannot be used on ' + @FieldName
                             + N', which holds ' + @fieldType + N'.';
                SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
            END;
        END;
    END;

    DECLARE @id int = @ConditionId, @action nvarchar(20);
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.DevEventCondition (SetId, FieldName, OperatorCode, Value1, Value2, SortOrder)
        VALUES (@SetId, @FieldName, @OperatorCode, @Value1, @Value2,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.DevEventCondition WHERE SetId = @SetId), 10));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.DevEventCondition SET FieldName = @FieldName, OperatorCode = @OperatorCode,
               Value1 = @Value1, Value2 = @Value2 WHERE ConditionId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.DevEventCondition', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;

    SELECT ConditionId = @id, Phrase = sel.fn_ConditionText(@id),
           RuleText = sel.fn_EventRuleText(@evId), RuleShort = sel.fn_EventRuleShort(@evId);
END
GO
PRINT '  sel.usp_EventCondition_Save       applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_EventCondition_Delete
    @LoginName   nvarchar(128),
    @ConditionId int,
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
    END;

    DECLARE @evId int = (SELECT cs.DevEventId FROM sel.DevEventCondition c
                         JOIN sel.DevEventConditionSet cs ON cs.SetId = c.SetId
                         WHERE c.ConditionId = @ConditionId);
    IF @evId IS NULL
    BEGIN
        SET @Problem = N'That condition no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS ConditionId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT FieldName, OperatorCode, Value1, Value2
                                     FROM sel.DevEventCondition WHERE ConditionId = @ConditionId
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM sel.DevEventCondition WHERE ConditionId = @ConditionId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @ConditionId);
    EXEC audit.usp_Log @TableName = N'sel.DevEventCondition', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;

    SELECT ConditionId = @ConditionId, Deleted = CAST(1 AS bit), RuleText = sel.fn_EventRuleText(@evId);
END
GO
PRINT '  sel.usp_EventCondition_Delete     applied';
GO

/* Reverting an override: an event with no sets follows its kind's default and says so. */
CREATE OR ALTER PROCEDURE sel.usp_EventRule_Revert
    @LoginName  nvarchar(128),
    @DevEventId int,
    @Problem    nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevEventId; RETURN;
    END;

    BEGIN TRAN;
    DELETE c FROM sel.DevEventCondition c
    JOIN sel.DevEventConditionSet cs ON cs.SetId = c.SetId WHERE cs.DevEventId = @DevEventId;
    DELETE FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevEventId);
    EXEC audit.usp_Log @TableName = N'sel.DevEventConditionSet', @KeyText = @keyText, @ActionCode = N'REVERT',
                       @LoginName = @LoginName;

    SELECT DevEventId = @DevEventId, RuleText = sel.fn_EventRuleText(@DevEventId);
END
GO
PRINT '  sel.usp_EventRule_Revert          applied';
GO

/* Equivalencies. */
CREATE OR ALTER PROCEDURE sel.usp_Equivalence_Add
    @LoginName          nvarchar(128),
    @MainItemCode       nvarchar(60),
    @EquivalentItemCode nvarchar(60),
    @Note               nvarchar(400) = NULL,
    @Problem            nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevEquivalenceId; RETURN;
    END;
    IF @MainItemCode = @EquivalentItemCode
    BEGIN
        SET @Problem = N'An item cannot be equivalent to itself.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEquivalenceId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.DevEquivalence WHERE MainItemCode = @MainItemCode AND EquivalentItemCode = @EquivalentItemCode)
    BEGIN
        SET @Problem = @EquivalentItemCode + N' already counts for ' + @MainItemCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS DevEquivalenceId; RETURN;
    END;
    /* The equivalent needs its own event, because the engine judges it by its own rule
       against its own source.  Warn rather than refuse: the event may come next. */
    DECLARE @hasOwnEvent bit = CASE WHEN EXISTS (SELECT 1 FROM sel.DevEvent
                                    WHERE ItemCode = @EquivalentItemCode AND IsActive = 1) THEN 1 ELSE 0 END;

    INSERT sel.DevEquivalence (MainItemCode, EquivalentItemCode, Note)
    VALUES (@MainItemCode, @EquivalentItemCode, @Note);
    DECLARE @id int = SCOPE_IDENTITY();

    DECLARE @keyText nvarchar(200) = @MainItemCode + N'/' + @EquivalentItemCode;
    EXEC audit.usp_Log @TableName = N'sel.DevEquivalence', @KeyText = @keyText, @ActionCode = N'INSERT',
                       @LoginName = @LoginName;

    SELECT DevEquivalenceId = @id, MainItemCode = @MainItemCode, EquivalentItemCode = @EquivalentItemCode,
           Warning = CASE WHEN @hasOwnEvent = 0
                          THEN @EquivalentItemCode + N' has no event of its own yet, so nothing can judge it. '
                             + N'Add an event with that code, or it will never count.'
                          ELSE NULL END;
END
GO
PRINT '  sel.usp_Equivalence_Add           applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Equivalence_Remove
    @LoginName        nvarchar(128),
    @DevEquivalenceId int,
    @Problem          nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevEquivalenceId; RETURN;
    END;
    DECLARE @before nvarchar(max) = (SELECT MainItemCode, EquivalentItemCode FROM sel.DevEquivalence
                                     WHERE DevEquivalenceId = @DevEquivalenceId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM sel.DevEquivalence WHERE DevEquivalenceId = @DevEquivalenceId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevEquivalenceId);
    EXEC audit.usp_Log @TableName = N'sel.DevEquivalence', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;
    SELECT DevEquivalenceId = @DevEquivalenceId, Removed = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Equivalence_Remove        applied';
GO

/* =====================================================================================
   Frameworks
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_Framework_Save
    @LoginName      nvarchar(128),
    @DevFrameworkId int = NULL,
    @FrameworkCode  nvarchar(60),
    @Name           nvarchar(300),
    @Description    nvarchar(600) = NULL,
    @StatusCode     nvarchar(60) = N'DRAFT',
    @UsesLevels     bit = 0,
    @MixtureModelId int = NULL,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;

    DECLARE @statusId int = cfg.fn_DomainValueId(N'FRAMEWORK_STATUS', @StatusCode);
    IF @statusId IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@StatusCode, N'') + N'" is not a framework status.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.DevFramework WHERE FrameworkCode = @FrameworkCode
                 AND (@DevFrameworkId IS NULL OR DevFrameworkId <> @DevFrameworkId))
    BEGIN
        SET @Problem = N'There is already a framework with the code ' + @FrameworkCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;
    /* Activating an empty framework would make it assignable and unsatisfiable. */
    IF @StatusCode = N'ACTIVE' AND @DevFrameworkId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM sel.DevFrameworkItem WHERE DevFrameworkId = @DevFrameworkId)
    BEGIN
        SET @Problem = N'This framework has no events in it yet, so there is nothing to make active.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;

    DECLARE @id int = @DevFrameworkId, @action nvarchar(20), @before nvarchar(max) = NULL;
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.DevFramework (FrameworkCode, Name, Description, StatusValueId, UsesLevels, MixtureModelId)
        VALUES (@FrameworkCode, @Name, @Description, @statusId, @UsesLevels, @MixtureModelId);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT FrameworkCode, Name, StatusValueId, UsesLevels, MixtureModelId
                       FROM sel.DevFramework WHERE DevFrameworkId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE sel.DevFramework
           SET FrameworkCode = @FrameworkCode, Name = @Name, Description = @Description,
               StatusValueId = @statusId, UsesLevels = @UsesLevels, MixtureModelId = @MixtureModelId
        WHERE DevFrameworkId = @id;

        /* "+ Use levels" converts the flat list into Level 1. */
        IF @UsesLevels = 1
            UPDATE sel.DevFrameworkItem SET LevelNo = 1, LevelName = ISNULL(LevelName, N'Level 1')
            WHERE DevFrameworkId = @id AND LevelNo IS NULL;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    DECLARE @after nvarchar(max) = (SELECT FrameworkCode, Name, StatusValueId, UsesLevels, MixtureModelId
                                    FROM sel.DevFramework WHERE DevFrameworkId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.DevFramework', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT DevFrameworkId = @id, FrameworkCode = @FrameworkCode, Name = @Name;
END
GO
PRINT '  sel.usp_Framework_Save            applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Framework_SaveItem
    @LoginName         nvarchar(128),
    @DevFrameworkId    int,
    @DevFrameworkItemId int = NULL,
    @DevEventId        int,
    @LevelNo           int = 1,
    @LevelName         nvarchar(120) = NULL,
    @Weight            decimal(9,4) = 0,
    @IsMust            bit = 0,
    @SortOrder         int = NULL,
    @Problem           nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkItemId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.DevEvent WHERE DevEventId = @DevEventId)
    BEGIN
        SET @Problem = N'That event no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkItemId; RETURN;
    END;
    IF @Weight < 0
    BEGIN
        SET @Problem = N'A weight cannot be negative.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkItemId; RETURN;
    END;
    /* The same event may sit in several levels, but not twice in one. */
    IF EXISTS (SELECT 1 FROM sel.DevFrameworkItem
               WHERE DevFrameworkId = @DevFrameworkId AND LevelNo = @LevelNo AND DevEventId = @DevEventId
                 AND (@DevFrameworkItemId IS NULL OR DevFrameworkItemId <> @DevFrameworkItemId))
    BEGIN
        SET @Problem = N'That event is already a requirement at this level.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkItemId; RETURN;
    END;

    DECLARE @id int = @DevFrameworkItemId, @action nvarchar(20);
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.DevFrameworkItem (DevFrameworkId, LevelNo, LevelName, DevEventId, Weight, IsMust, SortOrder)
        VALUES (@DevFrameworkId, @LevelNo, @LevelName, @DevEventId, @Weight, @IsMust,
                ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.DevFrameworkItem
                                           WHERE DevFrameworkId = @DevFrameworkId AND LevelNo = @LevelNo), 10)));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.DevFrameworkItem
           SET LevelNo = @LevelNo, LevelName = @LevelName, DevEventId = @DevEventId,
               Weight = @Weight, IsMust = @IsMust, SortOrder = ISNULL(@SortOrder, SortOrder)
        WHERE DevFrameworkItemId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.DevFrameworkItem', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;

    SELECT DevFrameworkItemId = @id,
           WeightTotal = (SELECT SUM(Weight) FROM sel.DevFrameworkItem WHERE DevFrameworkId = @DevFrameworkId),
           WeightTarget = cfg.fn_SettingNum(N'WEIGHT_TOTAL_TARGET');
END
GO
PRINT '  sel.usp_Framework_SaveItem        applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Framework_DeleteItem
    @LoginName          nvarchar(128),
    @DevFrameworkItemId int,
    @Problem            nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkItemId; RETURN;
    END;
    DECLARE @fw int = (SELECT DevFrameworkId FROM sel.DevFrameworkItem WHERE DevFrameworkItemId = @DevFrameworkItemId);
    DELETE FROM sel.DevFrameworkItem WHERE DevFrameworkItemId = @DevFrameworkItemId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevFrameworkItemId);
    EXEC audit.usp_Log @TableName = N'sel.DevFrameworkItem', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @LoginName = @LoginName;
    SELECT DevFrameworkItemId = @DevFrameworkItemId, Deleted = CAST(1 AS bit),
           WeightTotal = (SELECT SUM(Weight) FROM sel.DevFrameworkItem WHERE DevFrameworkId = @fw);
END
GO
PRINT '  sel.usp_Framework_DeleteItem      applied';
GO

/* Removing a level moves its requirements to the first, rather than dropping them. */
CREATE OR ALTER PROCEDURE sel.usp_Framework_RemoveLevel
    @LoginName      nvarchar(128),
    @DevFrameworkId int,
    @LevelNo        int,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS LevelNo; RETURN;
    END;

    DECLARE @firstLevel int = (SELECT MIN(LevelNo) FROM sel.DevFrameworkItem
                               WHERE DevFrameworkId = @DevFrameworkId AND LevelNo <> @LevelNo);
    IF @firstLevel IS NULL
    BEGIN
        SET @Problem = N'This is the only level, so its requirements have nowhere to move to.';
        SELECT TOP (0) CAST(NULL AS int) AS LevelNo; RETURN;
    END;

    BEGIN TRAN;
    /* Anything already at the first level stays there; the rest move down. */
    DELETE FROM sel.DevFrameworkItem
    WHERE DevFrameworkId = @DevFrameworkId AND LevelNo = @LevelNo
      AND DevEventId IN (SELECT DevEventId FROM sel.DevFrameworkItem
                         WHERE DevFrameworkId = @DevFrameworkId AND LevelNo = @firstLevel);

    UPDATE sel.DevFrameworkItem SET LevelNo = @firstLevel
    WHERE DevFrameworkId = @DevFrameworkId AND LevelNo = @LevelNo;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevFrameworkId) + N'/L' + CONVERT(nvarchar(10), @LevelNo);
    EXEC audit.usp_Log @TableName = N'sel.DevFrameworkItem', @KeyText = @keyText, @ActionCode = N'REMOVE_LEVEL',
                       @LoginName = @LoginName;
    SELECT LevelNo = @LevelNo, MovedTo = @firstLevel;
END
GO
PRINT '  sel.usp_Framework_RemoveLevel     applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Framework_Duplicate
    @LoginName      nvarchar(128),
    @DevFrameworkId int,
    @NewCode        nvarchar(60),
    @NewName        nvarchar(300),
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.DevFramework WHERE FrameworkCode = @NewCode)
    BEGIN
        SET @Problem = N'There is already a framework with the code ' + @NewCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;

    BEGIN TRAN;
    INSERT sel.DevFramework (FrameworkCode, Name, Description, StatusValueId, VersionNo, UsesLevels, MixtureModelId)
    SELECT @NewCode, @NewName, Description,
           cfg.fn_DomainValueId(N'FRAMEWORK_STATUS', N'DRAFT'), VersionNo + 1, UsesLevels, MixtureModelId
    FROM sel.DevFramework WHERE DevFrameworkId = @DevFrameworkId;
    DECLARE @newId int = SCOPE_IDENTITY();

    INSERT sel.DevFrameworkItem (DevFrameworkId, LevelNo, LevelName, DevEventId, Weight, IsMust, SortOrder)
    SELECT @newId, LevelNo, LevelName, DevEventId, Weight, IsMust, SortOrder
    FROM sel.DevFrameworkItem WHERE DevFrameworkId = @DevFrameworkId;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @newId);
    EXEC audit.usp_Log @TableName = N'sel.DevFramework', @KeyText = @keyText, @ActionCode = N'DUPLICATE',
                       @LoginName = @LoginName;
    SELECT DevFrameworkId = @newId, FrameworkCode = @NewCode, Name = @NewName;
END
GO
PRINT '  sel.usp_Framework_Duplicate       applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Framework_Retire
    @LoginName      nvarchar(128),
    @DevFrameworkId int,
    @RetiredOn      date = NULL,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;

    /* A framework a live cycle is measuring against cannot vanish underneath it. */
    DECLARE @live int = (SELECT COUNT(*) FROM sel.CycleFramework cf
                         JOIN sel.Cycle c ON c.CycleId = cf.CycleId
                         JOIN cfg.DomainValue dv ON dv.DomainValueId = c.StatusValueId
                         WHERE cf.DevFrameworkId = @DevFrameworkId AND dv.ValueCode = N'ACTIVE');
    IF @live > 0
    BEGIN
        SET @Problem = CONVERT(nvarchar(10), @live) + N' active cycle'
                     + CASE WHEN @live = 1 THEN N' is' ELSE N's are' END
                     + N' measuring against this framework, so it cannot be retired yet.';
        SELECT TOP (0) CAST(NULL AS int) AS DevFrameworkId; RETURN;
    END;

    UPDATE sel.DevFramework
       SET IsActive = 0, RetiredOn = ISNULL(@RetiredOn, CAST(SYSUTCDATETIME() AS date))
    WHERE DevFrameworkId = @DevFrameworkId;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevFrameworkId);
    EXEC audit.usp_Log @TableName = N'sel.DevFramework', @KeyText = @keyText, @ActionCode = N'RETIRE',
                       @LoginName = @LoginName;
    SELECT DevFrameworkId = @DevFrameworkId, Retired = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_Framework_Retire          applied';
GO

/* Mixture models. */
CREATE OR ALTER PROCEDURE sel.usp_MixtureModel_Save
    @LoginName      nvarchar(128),
    @MixtureModelId int = NULL,
    @ModelCode      nvarchar(40),
    @Name           nvarchar(160),
    @Description    nvarchar(400) = NULL,
    @TolerancePct   decimal(9,4) = 5,
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS MixtureModelId; RETURN;
    END;
    IF EXISTS (SELECT 1 FROM sel.MixtureModel WHERE ModelCode = @ModelCode
                 AND (@MixtureModelId IS NULL OR MixtureModelId <> @MixtureModelId))
    BEGIN
        SET @Problem = N'There is already a model with the code ' + @ModelCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS MixtureModelId; RETURN;
    END;

    DECLARE @id int = @MixtureModelId, @action nvarchar(20);
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT sel.MixtureModel (ModelCode, Name, Description, TolerancePct)
        VALUES (@ModelCode, @Name, @Description, @TolerancePct);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.MixtureModel SET ModelCode = @ModelCode, Name = @Name,
               Description = @Description, TolerancePct = @TolerancePct
        WHERE MixtureModelId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.MixtureModel', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;
    SELECT MixtureModelId = @id, ModelCode = @ModelCode, Name = @Name;
END
GO
PRINT '  sel.usp_MixtureModel_Save         applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_MixturePart_Save
    @LoginName      nvarchar(128),
    @MixtureModelId int,
    @PartCode       nvarchar(60),
    @TargetPct      decimal(9,4),
    @Problem        nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS MixturePartId; RETURN;
    END;

    DECLARE @partId int = cfg.fn_DomainValueId(N'PART', @PartCode);
    IF @partId IS NULL
    BEGIN
        SET @Problem = N'"' + ISNULL(@PartCode, N'') + N'" is not one of the mixture parts.';
        SELECT TOP (0) CAST(NULL AS int) AS MixturePartId; RETURN;
    END;
    IF @TargetPct < 0 OR @TargetPct > 100
    BEGIN
        SET @Problem = N'A target is a percentage, so it sits between 0 and 100.';
        SELECT TOP (0) CAST(NULL AS int) AS MixturePartId; RETURN;
    END;

    DECLARE @id int = (SELECT MixturePartId FROM sel.MixturePart
                       WHERE MixtureModelId = @MixtureModelId AND PartValueId = @partId);
    IF @id IS NULL
    BEGIN
        INSERT sel.MixturePart (MixtureModelId, PartValueId, TargetPct, SortOrder)
        VALUES (@MixtureModelId, @partId, @TargetPct,
                ISNULL((SELECT MAX(SortOrder) + 10 FROM sel.MixturePart WHERE MixtureModelId = @MixtureModelId), 10));
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE sel.MixturePart SET TargetPct = @TargetPct WHERE MixturePartId = @id;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.MixturePart', @KeyText = @keyText, @ActionCode = N'SAVE',
                       @LoginName = @LoginName;

    SELECT MixturePartId = @id,
           PartTotal = (SELECT SUM(TargetPct) FROM sel.MixturePart WHERE MixtureModelId = @MixtureModelId);
END
GO
PRINT '  sel.usp_MixturePart_Save          applied';
GO

/* =====================================================================================
   Evidence sources, roster fields, reference data, the catalogue
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_EvidenceSource_Save
    @LoginName     nvarchar(128),
    @KindCode      nvarchar(30),
    @SourceKey     nvarchar(40) = NULL,
    @ItemColumn    nvarchar(128) = NULL,
    @StatusColumn  nvarchar(128) = NULL,
    @PassValue     nvarchar(120) = NULL,
    @MeasureColumn nvarchar(128) = NULL,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS EvidenceSourceId; RETURN;
    END;

    DECLARE @id int = (SELECT EvidenceSourceId FROM sel.EvidenceSource WHERE KindCode = @KindCode);
    IF @id IS NULL
    BEGIN
        SET @Problem = N'There is no evidence source for the kind ' + ISNULL(@KindCode, N'') + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS EvidenceSourceId; RETURN;
    END;
    IF @SourceKey IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sel.TableMapping WHERE SourceKey = @SourceKey)
    BEGIN
        SET @Problem = N'"' + @SourceKey + N'" is not a source this application maps.';
        SELECT TOP (0) CAST(NULL AS int) AS EvidenceSourceId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT KindCode, SourceKey, ItemColumn, StatusColumn, PassValue, MeasureColumn
                                     FROM sel.EvidenceSource WHERE EvidenceSourceId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    UPDATE sel.EvidenceSource
       SET SourceKey = ISNULL(@SourceKey, SourceKey), ItemColumn = @ItemColumn,
           StatusColumn = @StatusColumn, PassValue = @PassValue, MeasureColumn = @MeasureColumn
    WHERE EvidenceSourceId = @id;

    DECLARE @keyText nvarchar(200) = @KindCode;
    DECLARE @after nvarchar(max) = (SELECT KindCode, SourceKey, ItemColumn, StatusColumn, PassValue, MeasureColumn
                                    FROM sel.EvidenceSource WHERE EvidenceSourceId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.EvidenceSource', @KeyText = @keyText, @ActionCode = N'UPDATE',
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT EvidenceSourceId = @id, KindCode = @KindCode;
END
GO
PRINT '  sel.usp_EvidenceSource_Save       applied';
GO

/* Approving a roster field makes it available to the criteria builder.  Enabled and
   sensitive are different questions, and the screen has to say so.                     */
CREATE OR ALTER PROCEDURE sel.usp_RosterField_Save
    @LoginName     nvarchar(128),
    @RosterFieldId int,
    @Caption       nvarchar(160) = NULL,
    @IsEnabled     bit = NULL,
    @IsSensitive   bit = NULL,
    @GroupName     nvarchar(80) = NULL,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Config/RosterFields/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS RosterFieldId; RETURN;
    END;

    DECLARE @fieldName nvarchar(128) = (SELECT FieldName FROM sel.RosterField WHERE RosterFieldId = @RosterFieldId);
    IF @fieldName IS NULL
    BEGIN
        SET @Problem = N'That field no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS RosterFieldId; RETURN;
    END;

    /* Marking a field sensitive while criteria still filter on it would silently change
       what those cycles mean, so say what is in the way instead. */
    IF @IsSensitive = 1
    BEGIN
        DECLARE @inUse int = (SELECT COUNT(*) FROM sel.CycleCriterion WHERE RosterFieldId = @RosterFieldId);
        IF @inUse > 0
        BEGIN
            SET @Problem = @fieldName + N' is used by ' + CONVERT(nvarchar(10), @inUse)
                         + N' criteri' + CASE WHEN @inUse = 1 THEN N'on' ELSE N'a' END
                         + N'. Remove those before marking it sensitive.';
            SELECT TOP (0) CAST(NULL AS int) AS RosterFieldId; RETURN;
        END;
    END;

    DECLARE @before nvarchar(max) = (SELECT FieldName, Caption, IsEnabled, IsSensitive, GroupName
                                     FROM sel.RosterField WHERE RosterFieldId = @RosterFieldId
                                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    UPDATE sel.RosterField
       SET Caption = ISNULL(@Caption, Caption),
           IsSensitive = ISNULL(@IsSensitive, IsSensitive),
           GroupName = ISNULL(@GroupName, GroupName),
           /* A sensitive field is never usable in criteria, whatever else was asked. */
           IsEnabled = CONVERT(bit, CASE WHEN ISNULL(@IsSensitive, IsSensitive) = 1 THEN 0
                            ELSE ISNULL(@IsEnabled, IsEnabled) END)
    WHERE RosterFieldId = @RosterFieldId;

    DECLARE @keyText nvarchar(200) = @fieldName;
    DECLARE @after nvarchar(max) = (SELECT FieldName, Caption, IsEnabled, IsSensitive, GroupName
                                    FROM sel.RosterField WHERE RosterFieldId = @RosterFieldId
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'sel.RosterField', @KeyText = @keyText, @ActionCode = N'UPDATE',
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT RosterFieldId, FieldName, Caption, IsEnabled, IsSensitive, GroupName
    FROM sel.RosterField WHERE RosterFieldId = @RosterFieldId;
END
GO
PRINT '  sel.usp_RosterField_Save          applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_DomainValue_Save
    @LoginName     nvarchar(128),
    @DomainCode    nvarchar(60),
    @DomainValueId int = NULL,
    @ValueCode     nvarchar(60),
    @Name          nvarchar(160),
    @Description   nvarchar(400) = NULL,
    @SemanticRole  nvarchar(40) = NULL,
    @SortOrder     int = NULL,
    @IsActive      bit = 1,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Config/RefData/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    DECLARE @domainId int, @domainIsSystem bit, @domainName nvarchar(120);
    SELECT @domainId = DomainId, @domainIsSystem = IsSystem, @domainName = Name
    FROM cfg.Domain WHERE DomainCode = @DomainCode;
    IF @domainId IS NULL
    BEGIN
        SET @Problem = N'There is no reference list called ' + ISNULL(@DomainCode, N'') + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    /* A system domain's codes are referenced by the engine.  Renaming one is fine;
       changing its code is not, and the refusal says why. */
    IF @DomainValueId IS NOT NULL AND @domainIsSystem = 1
    BEGIN
        DECLARE @existingCode nvarchar(60) = (SELECT ValueCode FROM cfg.DomainValue WHERE DomainValueId = @DomainValueId);
        IF @existingCode <> @ValueCode
        BEGIN
            SET @Problem = N'"' + @domainName + N'" is a system list. Its codes are used by the engine, '
                         + N'so a value can be renamed but its code cannot be changed.';
            SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
        END;
    END;

    IF EXISTS (SELECT 1 FROM cfg.DomainValue WHERE DomainId = @domainId AND ValueCode = @ValueCode
                 AND (@DomainValueId IS NULL OR DomainValueId <> @DomainValueId))
    BEGIN
        SET @Problem = N'"' + @domainName + N'" already has a value with the code ' + @ValueCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    DECLARE @id int = @DomainValueId, @action nvarchar(20), @before nvarchar(max) = NULL;
    IF @id IS NULL
    BEGIN
        SET @action = N'INSERT';
        INSERT cfg.DomainValue (DomainId, ValueCode, Name, Description, SemanticRole, SortOrder, IsActive, IsSystem)
        VALUES (@domainId, @ValueCode, @Name, @Description, @SemanticRole,
                ISNULL(@SortOrder, ISNULL((SELECT MAX(SortOrder) + 10 FROM cfg.DomainValue WHERE DomainId = @domainId), 10)),
                @IsActive, 0);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        SET @before = (SELECT ValueCode, Name, SemanticRole, SortOrder, IsActive FROM cfg.DomainValue
                       WHERE DomainValueId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        UPDATE cfg.DomainValue
           SET ValueCode = @ValueCode, Name = @Name, Description = @Description,
               SemanticRole = @SemanticRole, SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = @IsActive
        WHERE DomainValueId = @id;
    END;

    DECLARE @keyText nvarchar(200) = @DomainCode + N'/' + @ValueCode;
    DECLARE @after nvarchar(max) = (SELECT ValueCode, Name, SemanticRole, SortOrder, IsActive FROM cfg.DomainValue
                                    WHERE DomainValueId = @id FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC audit.usp_Log @TableName = N'cfg.DomainValue', @KeyText = @keyText, @ActionCode = @action,
                       @BeforeJson = @before, @AfterJson = @after, @LoginName = @LoginName;

    SELECT DomainValueId = @id, DomainCode = @DomainCode, ValueCode = @ValueCode, Name = @Name;
END
GO
PRINT '  sel.usp_DomainValue_Save          applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_DomainValue_Delete
    @LoginName     nvarchar(128),
    @DomainValueId int,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Config/RefData/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    DECLARE @isSystem bit, @code nvarchar(60), @domainName nvarchar(120);
    SELECT @isSystem = CASE WHEN dv.IsSystem = 1 OR d.IsSystem = 1 THEN 1 ELSE 0 END,
           @code = dv.ValueCode, @domainName = d.Name
    FROM cfg.DomainValue dv JOIN cfg.Domain d ON d.DomainId = dv.DomainId
    WHERE dv.DomainValueId = @DomainValueId;

    IF @code IS NULL
    BEGIN
        SET @Problem = N'That value no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    /* A system domain refuses deletion of a code, and says why. */
    IF @isSystem = 1
    BEGIN
        SET @Problem = N'"' + @code + N'" is part of ' + @domainName
                     + N', which the engine reads by code. Deactivate it instead of deleting it.';
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    /* Something that is in use is deactivated, not removed, so the history still reads. */
    IF EXISTS (SELECT 1 FROM sel.CandidateDecision WHERE DecisionValueId = @DomainValueId)
    OR EXISTS (SELECT 1 FROM sel.CycleStage WHERE PerformerLevelValueId = @DomainValueId)
    OR EXISTS (SELECT 1 FROM sel.DevEvent WHERE EventTypeValueId = @DomainValueId OR PartValueId = @DomainValueId
                  OR MeasureValueId = @DomainValueId OR PhaseValueId = @DomainValueId)
    BEGIN
        SET @Problem = N'"' + @code + N'" is already used by something recorded, so it is deactivated rather than deleted.';
        UPDATE cfg.DomainValue SET IsActive = 0 WHERE DomainValueId = @DomainValueId;
        SELECT TOP (0) CAST(NULL AS int) AS DomainValueId; RETURN;
    END;

    DECLARE @before nvarchar(max) = (SELECT ValueCode, Name FROM cfg.DomainValue
                                     WHERE DomainValueId = @DomainValueId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DELETE FROM cfg.DomainValue WHERE DomainValueId = @DomainValueId;

    DECLARE @keyText nvarchar(200) = @code;
    EXEC audit.usp_Log @TableName = N'cfg.DomainValue', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @BeforeJson = @before, @LoginName = @LoginName;
    SELECT DomainValueId = @DomainValueId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_DomainValue_Delete        applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CatalogItem_Save
    @LoginName     nvarchar(128),
    @CatalogItemId int = NULL,
    @ItemCode      nvarchar(60),
    @Name          nvarchar(300),
    @KindCode      nvarchar(30),
    @CategoryCode  nvarchar(60) = NULL,
    @NeedsReview   bit = 0,
    @IsActive      bit = 1,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Config/RefData/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS CatalogItemId; RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sel.RequirementKind WHERE KindCode = @KindCode)
    BEGIN
        SET @Problem = N'"' + ISNULL(@KindCode, N'') + N'" is not a requirement kind this application knows.';
        SELECT TOP (0) CAST(NULL AS int) AS CatalogItemId; RETURN;
    END;

    DECLARE @catId int = CASE WHEN @CategoryCode IS NULL THEN NULL
                              ELSE cfg.fn_DomainValueId(N'ITEM_CATEGORY', @CategoryCode) END;

    DECLARE @id int = @CatalogItemId, @action nvarchar(20);
    IF @id IS NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM sel.CatalogItem WHERE KindCode = @KindCode AND ItemCode = @ItemCode)
        BEGIN
            SET @Problem = N'The catalogue already has ' + @ItemCode + N' under that kind.';
            SELECT TOP (0) CAST(NULL AS int) AS CatalogItemId; RETURN;
        END;
        SET @action = N'INSERT';
        INSERT sel.CatalogItem (ItemCode, Name, KindCode, CategoryValueId, NeedsReview, IsActive)
        VALUES (@ItemCode, @Name, @KindCode, @catId, @NeedsReview, @IsActive);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        SET @action = N'UPDATE';
        UPDATE sel.CatalogItem SET ItemCode = @ItemCode, Name = @Name, KindCode = @KindCode,
               CategoryValueId = @catId, NeedsReview = @NeedsReview, IsActive = @IsActive
        WHERE CatalogItemId = @id;
    END;

    DECLARE @keyText nvarchar(200) = @ItemCode;
    EXEC audit.usp_Log @TableName = N'sel.CatalogItem', @KeyText = @keyText, @ActionCode = @action,
                       @LoginName = @LoginName;
    SELECT CatalogItemId = @id, ItemCode = @ItemCode, Name = @Name;
END
GO
PRINT '  sel.usp_CatalogItem_Save          applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_CatalogItem_Delete
    @LoginName     nvarchar(128),
    @CatalogItemId int,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Config/RefData/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS CatalogItemId; RETURN;
    END;

    DECLARE @code nvarchar(60), @kind nvarchar(30);
    SELECT @code = ItemCode, @kind = KindCode FROM sel.CatalogItem WHERE CatalogItemId = @CatalogItemId;
    IF @code IS NULL
    BEGIN
        SET @Problem = N'That catalogue item no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS CatalogItemId; RETURN;
    END;

    DECLARE @records int = (SELECT COUNT(*) FROM sel.EmployeeRecord WHERE KindCode = @kind AND ItemCode = @code);
    IF @records > 0
    BEGIN
        SET @Problem = CONVERT(nvarchar(20), @records) + N' people have a record against ' + @code
                     + N', so it is deactivated rather than deleted.';
        UPDATE sel.CatalogItem SET IsActive = 0 WHERE CatalogItemId = @CatalogItemId;
        SELECT TOP (0) CAST(NULL AS int) AS CatalogItemId; RETURN;
    END;

    DELETE FROM sel.CatalogItem WHERE CatalogItemId = @CatalogItemId;
    DECLARE @keyText nvarchar(200) = @code;
    EXEC audit.usp_Log @TableName = N'sel.CatalogItem', @KeyText = @keyText, @ActionCode = N'DELETE',
                       @LoginName = @LoginName;
    SELECT CatalogItemId = @CatalogItemId, Deleted = CAST(1 AS bit);
END
GO
PRINT '  sel.usp_CatalogItem_Delete        applied';
GO

PRINT '== 10_crud complete ==================================================';
GO
