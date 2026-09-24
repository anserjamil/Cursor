/* =====================================================================================
   12_idp.sql  —  the individual development plan
   -------------------------------------------------------------------------------------
   The IDP stage is where a planner turns unmet requirements into booked, dated, approved
   plans.  The rules the prototype fixes, which these procedures hold:

     * "Plan created" means every open requirement for that person has a booking, a
       pencilled date, or assigned coverage days.  Nothing else counts.
     * Approval is at plan level, never per requirement.
     * Coverage is never auto-assigned — coverage costs leave, and that is a human
       decision.
     * Two requirements with the same name from different sources show their item code,
       so they cannot be confused.
     * After a person's plan completes they stay on screen in the finished state with the
       Approve button; the list does not re-sort them away under the cursor.
     * The target completion date tightens with readiness: the stage-window start plus
       (levelIndex + 1) x 6 months, overridable per person.  An open plan past its target
       reads as overdue.
     * Read only outside the stage window unless test mode.
     * A course is booked onto a SESSION, not a date, and a session has seats.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 12_idp ============================================================';
GO

/* --- sel.DevSession -------------------------------------------------------------
   A schedule: a course is booked onto one of these, not onto a date.                */
IF OBJECT_ID('sel.DevSession') IS NULL
BEGIN
    CREATE TABLE sel.DevSession
    (
        DevSessionId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevSession PRIMARY KEY,
        DevEventId   int           NOT NULL CONSTRAINT FK_sel_DevSession_Event REFERENCES sel.DevEvent(DevEventId),
        SessionCode  nvarchar(60)  NOT NULL,
        StartDate    date          NULL,
        EndDate      date          NULL,
        Seats        int           NULL,          -- NULL means no limit
        Location     nvarchar(200) NULL,
        IsCancelled  bit           NOT NULL CONSTRAINT DF_sel_DevSession_Cancelled DEFAULT (0),
        CreatedOnUtc datetime2(3)  NOT NULL CONSTRAINT DF_sel_DevSession_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_DevSession UNIQUE (DevEventId, SessionCode)
    );
    CREATE INDEX IX_sel_DevSession_Event ON sel.DevSession (DevEventId, StartDate) INCLUDE (Seats, IsCancelled);
    PRINT '  sel.DevSession                    created';
END
ELSE PRINT '  sel.DevSession                    skipped';
GO

/* --- sel.IdpItem ----------------------------------------------------------------
   One person's obligation against one event, in one cycle.                          */
IF OBJECT_ID('sel.IdpItem') IS NULL
BEGIN
    CREATE TABLE sel.IdpItem
    (
        IdpItemId     bigint       IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_IdpItem PRIMARY KEY,
        CycleId       int          NOT NULL CONSTRAINT FK_sel_IdpItem_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo   nvarchar(30) NOT NULL,
        DevEventId    int          NOT NULL CONSTRAINT FK_sel_IdpItem_Event REFERENCES sel.DevEvent(DevEventId),
        /* A booking names a session; a pencilled date names no session at all. */
        DevSessionId  int          NULL CONSTRAINT FK_sel_IdpItem_Session REFERENCES sel.DevSession(DevSessionId),
        PencilledDate date         NULL,
        StatusValueId int          NOT NULL CONSTRAINT FK_sel_IdpItem_Status REFERENCES cfg.DomainValue(DomainValueId),
        SourceValueId int          NULL CONSTRAINT FK_sel_IdpItem_Source REFERENCES cfg.DomainValue(DomainValueId),
        OrgCode       nvarchar(40) NULL,
        ActorLogin    nvarchar(128) NULL,
        ChangedOnUtc  datetime2(3) NOT NULL CONSTRAINT DF_sel_IdpItem_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_IdpItem UNIQUE (CycleId, PersonnelNo, DevEventId)
    );
    CREATE INDEX IX_sel_IdpItem_Cycle   ON sel.IdpItem (CycleId, OrgCode) INCLUDE (PersonnelNo, DevEventId, StatusValueId);
    CREATE INDEX IX_sel_IdpItem_Session ON sel.IdpItem (DevSessionId);
    PRINT '  sel.IdpItem                       created';
END
ELSE PRINT '  sel.IdpItem                       skipped';
GO

/* --- sel.IdpCoverage ------------------------------------------------------------
   An acting assignment.  The day count is computed in SQL, and the person's remaining
   coverage balance is deducted and persisted.                                        */
IF OBJECT_ID('sel.IdpCoverage') IS NULL
BEGIN
    CREATE TABLE sel.IdpCoverage
    (
        IdpCoverageId bigint       IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_IdpCoverage PRIMARY KEY,
        CycleId      int           NOT NULL CONSTRAINT FK_sel_IdpCoverage_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo  nvarchar(30)  NOT NULL,
        DevEventId   int           NULL CONSTRAINT FK_sel_IdpCoverage_Event REFERENCES sel.DevEvent(DevEventId),
        Department   nvarchar(200) NULL,
        PositionCode nvarchar(60)  NULL,
        IncumbentPersonnelNo nvarchar(30) NULL,
        StartDate    date          NOT NULL,
        EndDate      date          NOT NULL,
        Days         int           NOT NULL,
        OrgCode      nvarchar(40)  NULL,
        ActorLogin   nvarchar(128) NOT NULL,
        AddedOnUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_IdpCoverage_On DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_sel_IdpCoverage_Person ON sel.IdpCoverage (CycleId, PersonnelNo);
    PRINT '  sel.IdpCoverage                   created';
END
ELSE PRINT '  sel.IdpCoverage                   skipped';
GO

/* --- sel.IdpTarget / sel.IdpNote / sel.IdpApproval ------------------------------ */
IF OBJECT_ID('sel.IdpTarget') IS NULL
BEGIN
    CREATE TABLE sel.IdpTarget
    (
        CycleId      int          NOT NULL CONSTRAINT FK_sel_IdpTarget_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo  nvarchar(30) NOT NULL,
        /* NULL means derived from the readiness level. */
        TargetDate   date         NULL,
        SetByLogin   nvarchar(128) NULL,
        SetOnUtc     datetime2(3) NOT NULL CONSTRAINT DF_sel_IdpTarget_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_sel_IdpTarget PRIMARY KEY (CycleId, PersonnelNo)
    );
    PRINT '  sel.IdpTarget                     created';
END
ELSE PRINT '  sel.IdpTarget                     skipped';
GO

IF OBJECT_ID('sel.IdpNote') IS NULL
BEGIN
    CREATE TABLE sel.IdpNote
    (
        IdpNoteId   bigint        IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_IdpNote PRIMARY KEY,
        CycleId     int           NOT NULL CONSTRAINT FK_sel_IdpNote_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo nvarchar(30)  NOT NULL,
        NoteText    nvarchar(max) NOT NULL,
        ActorLogin  nvarchar(128) NOT NULL,
        AddedOnUtc  datetime2(3)  NOT NULL CONSTRAINT DF_sel_IdpNote_On DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_sel_IdpNote ON sel.IdpNote (CycleId, PersonnelNo, AddedOnUtc DESC);
    PRINT '  sel.IdpNote                       created';
END
ELSE PRINT '  sel.IdpNote                       skipped';
GO

IF OBJECT_ID('sel.IdpApproval') IS NULL
BEGIN
    CREATE TABLE sel.IdpApproval
    (
        CycleId        int          NOT NULL CONSTRAINT FK_sel_IdpApproval_Cycle REFERENCES sel.Cycle(CycleId),
        PersonnelNo    nvarchar(30) NOT NULL,
        ApprovedByLogin nvarchar(128) NOT NULL,
        ApprovedOnUtc  datetime2(3) NOT NULL CONSTRAINT DF_sel_IdpApproval_On DEFAULT (SYSUTCDATETIME()),
        NotifiedOnUtc  datetime2(3) NULL,
        OrgCode        nvarchar(40) NULL,
        CONSTRAINT PK_sel_IdpApproval PRIMARY KEY (CycleId, PersonnelNo)
    );
    PRINT '  sel.IdpApproval                   created';
END
ELSE PRINT '  sel.IdpApproval                   skipped';
GO

/* =====================================================================================
   Helpers
   ===================================================================================== */

/* sel.fn_IdpTargetDate — the target completion date, derived and overridable.
   The stage window start plus (levelIndex + 1) x the configured months per level, so
   R1 is six months.  One implementation: the board, the person tab and the overdue
   test all read the same answer.                                                      */
CREATE OR ALTER FUNCTION sel.fn_IdpTargetDate
(
    @CycleId      int,
    @PersonnelNo  nvarchar(30),
    @CycleStageId int
)
RETURNS date
AS
BEGIN
    /* An explicit override always wins. */
    DECLARE @override date;
    SELECT @override = TargetDate FROM sel.IdpTarget
    WHERE CycleId = @CycleId AND PersonnelNo = @PersonnelNo;
    IF @override IS NOT NULL RETURN @override;

    DECLARE @windowStart date;
    SELECT @windowStart = StartDate FROM sel.CycleStage WHERE CycleStageId = @CycleStageId;
    IF @windowStart IS NULL
        SELECT @windowStart = StartDate FROM sel.Cycle WHERE CycleId = @CycleId;
    IF @windowStart IS NULL RETURN NULL;

    DECLARE @months int = CAST(ISNULL(cfg.fn_SettingNum(N'IDP_TARGET_MONTHS_PER_LEVEL'), 6) AS int);

    /* The person's level, as an index down the ladder: the first level is 0. */
    DECLARE @levelIndex int;
    SELECT @levelIndex = x.Idx - 1
    FROM (SELECT lv.LevelCode, Idx = ROW_NUMBER() OVER (ORDER BY lv.SortOrder)
          FROM sel.CycleReadiness lv WHERE lv.CycleId = @CycleId) x
    WHERE x.LevelCode = (SELECT TOP (1) r.LevelCode FROM sel.SuccessionPlanRow r
                         WHERE r.CycleId = @CycleId AND r.PersonnelNo = @PersonnelNo AND r.IsDropped = 0
                         ORDER BY r.DecidedOnUtc DESC);

    /* Somebody with no level yet is given the longest run, not the shortest. */
    IF @levelIndex IS NULL
        SELECT @levelIndex = ISNULL(COUNT(*), 1) - 1 FROM sel.CycleReadiness WHERE CycleId = @CycleId;

    RETURN DATEADD(MONTH, (@levelIndex + 1) * @months, @windowStart);
END
GO
PRINT '  sel.fn_IdpTargetDate              applied';
GO

/* sel.usp_Idp_OpenRequirements_Into — every obligation in the cohort, with whether it is
   already met.  The caller creates #scope (PersonnelNo) and #obl.

   Two sources naming the same event produce ONE row that names both, so the same course
   is never booked twice under two different headings.                                  */
CREATE OR ALTER PROCEDURE sel.usp_Idp_OpenRequirements_Into
    @CycleId int,
    @AsOf    date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    CREATE TABLE #met
    (
        PersonnelNo nvarchar(30)  NOT NULL, ItemCode nvarchar(60) NOT NULL,
        Met bit NOT NULL, Why nvarchar(600) NULL,
        NumValue decimal(18,4) NULL, Target decimal(18,4) NULL, ViaCode nvarchar(60) NULL
    );

    /* What the cycle asks for, and which source asks for it. */
    CREATE TABLE #req
    (
        DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        LevelNo int NOT NULL, IsMust bit NOT NULL, SourceCode nvarchar(20) NOT NULL,
        PRIMARY KEY (DevEventId, SourceCode, LevelNo)
    );

    /* Source 1: the readiness levels, through the assigned frameworks. */
    INSERT #req (DevEventId, ItemCode, LevelNo, IsMust, SourceCode)
    SELECT DISTINCT i.DevEventId, e.ItemCode, i.LevelNo, i.IsMust, N'LEVEL'
    FROM sel.CycleFramework cf
    JOIN sel.DevFrameworkItem i ON i.DevFrameworkId = cf.DevFrameworkId
    JOIN sel.DevEvent e ON e.DevEventId = i.DevEventId
    WHERE cf.CycleId = @CycleId AND e.ItemCode IS NOT NULL AND e.IsActive = 1;

    /* Source 2: requirements the cycle adds on top of its frameworks. */
    INSERT #req (DevEventId, ItemCode, LevelNo, IsMust, SourceCode)
    SELECT DISTINCT r.DevEventId, e.ItemCode, 1, r.IsMust, N'PLAN'
    FROM sel.CycleRequirement r
    JOIN sel.DevEvent e ON e.DevEventId = r.DevEventId
    WHERE r.CycleId = @CycleId AND e.ItemCode IS NOT NULL AND e.IsActive = 1
      AND NOT EXISTS (SELECT 1 FROM #req q WHERE q.DevEventId = r.DevEventId AND q.SourceCode = N'PLAN' AND q.LevelNo = 1);

    /* Judge every item once across the whole cohort — set-based, one statement per item. */
    DECLARE @item nvarchar(60);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT ItemCode FROM #req;
    OPEN c; FETCH NEXT FROM c INTO @item;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sel.usp_Item_ResolveMet_Into @ItemCode = @item, @AsOf = @AsOf;
        FETCH NEXT FROM c INTO @item;
    END;
    CLOSE c; DEALLOCATE c;

    /* One row per person x event, with every source that asks for it named. */
    INSERT #obl (PersonnelNo, DevEventId, ItemCode, EventCode, EventName, KindCode,
                 IsMust, IsMet, Why, Sources, LevelNo)
    SELECT s.PersonnelNo,
           r.DevEventId,
           r.ItemCode,
           e.EventCode,
           e.Name,
           e.KindCode,
           IsMust = MAX(CAST(r.IsMust AS int)),
           IsMet  = ISNULL(MAX(CAST(m.Met AS int)), 0),
           Why    = MAX(m.Why),
           /* "the row names both" */
           Sources = STUFF((SELECT N', ' + sv.Name
                            FROM (SELECT DISTINCT SourceCode FROM #req q
                                  WHERE q.DevEventId = r.DevEventId) z
                            JOIN cfg.DomainValue sv ON sv.DomainValueId = cfg.fn_DomainValueId(N'IDP_SOURCE', z.SourceCode)
                            ORDER BY sv.Name
                            FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N''),
           LevelNo = MIN(r.LevelNo)
    FROM #scope s
    CROSS JOIN #req r
    JOIN sel.DevEvent e ON e.DevEventId = r.DevEventId
    LEFT JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
    GROUP BY s.PersonnelNo, r.DevEventId, r.ItemCode, e.EventCode, e.Name, e.KindCode;

    DROP TABLE #req; DROP TABLE #met;
END
GO
PRINT '  sel.usp_Idp_OpenRequirements_Into applied';
GO

/* sel.fn_IdpPlanState — "plan created" means every open requirement has a booking, a
   pencilled date, or assigned coverage days.  Nothing else counts.                    */
CREATE OR ALTER FUNCTION sel.fn_IdpPlanState (@CycleId int, @PersonnelNo nvarchar(30), @OpenCount int, @PlannedCount int)
RETURNS nvarchar(20)
WITH SCHEMABINDING
AS
BEGIN
    IF EXISTS (SELECT 1 FROM sel.IdpApproval a WHERE a.CycleId = @CycleId AND a.PersonnelNo = @PersonnelNo)
        RETURN N'APPROVED';
    IF @OpenCount = 0                   RETURN N'COMPLETE';
    IF @PlannedCount = 0                RETURN N'NO_PLAN';
    IF @PlannedCount >= @OpenCount      RETURN N'COMPLETE';
    RETURN N'IN_PROGRESS';
END
GO
PRINT '  sel.fn_IdpPlanState               applied';
GO

/* sel.usp_Idp_Session_List / _Save — a course is booked onto a session, and a session
   has seats.                                                                          */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Session_List
    @LoginName  nvarchar(128),
    @DevEventId int = NULL,
    @CycleId    int = NULL,
    @FromDate   date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.DevSessionId, s.DevEventId, e.EventCode, e.Name AS EventName,
           s.SessionCode, s.StartDate, s.EndDate, s.Seats, s.Location, s.IsCancelled,
           Booked = (SELECT COUNT(*) FROM sel.IdpItem i WHERE i.DevSessionId = s.DevSessionId),
           SeatsLeft = CASE WHEN s.Seats IS NULL THEN NULL
                            ELSE s.Seats - (SELECT COUNT(*) FROM sel.IdpItem i WHERE i.DevSessionId = s.DevSessionId) END
    FROM sel.DevSession s
    JOIN sel.DevEvent e ON e.DevEventId = s.DevEventId
    WHERE (@DevEventId IS NULL OR s.DevEventId = @DevEventId)
      AND (@FromDate IS NULL OR s.StartDate IS NULL OR s.StartDate >= @FromDate)
      AND s.IsCancelled = 0
    ORDER BY e.EventCode, ISNULL(s.StartDate, '9999-12-31'), s.SessionCode;
END
GO
PRINT '  sel.usp_Idp_Session_List          applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Idp_Session_Save
    @LoginName    nvarchar(128),
    @DevSessionId int = NULL,
    @DevEventId   int,
    @SessionCode  nvarchar(60),
    @StartDate    date = NULL,
    @EndDate      date = NULL,
    @Seats        int = NULL,
    @Location     nvarchar(200) = NULL,
    @IsCancelled  bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS DevSessionId; RETURN;
    END;
    IF @StartDate IS NOT NULL AND @EndDate IS NOT NULL AND @EndDate < @StartDate
    BEGIN
        SET @Problem = N'That session ends before it starts.';
        SELECT TOP (0) CAST(NULL AS int) AS DevSessionId; RETURN;
    END;

    DECLARE @id int = @DevSessionId;
    IF @id IS NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM sel.DevSession WHERE DevEventId = @DevEventId AND SessionCode = @SessionCode)
        BEGIN
            SET @Problem = N'That event already has a session called ' + @SessionCode + N'.';
            SELECT TOP (0) CAST(NULL AS int) AS DevSessionId; RETURN;
        END;
        INSERT sel.DevSession (DevEventId, SessionCode, StartDate, EndDate, Seats, Location, IsCancelled)
        VALUES (@DevEventId, @SessionCode, @StartDate, @EndDate, @Seats, @Location, @IsCancelled);
        SET @id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        /* Cutting seats below what is already booked would make the session over-booked
           with nobody having done anything wrong. */
        DECLARE @booked int = (SELECT COUNT(*) FROM sel.IdpItem WHERE DevSessionId = @id);
        IF @Seats IS NOT NULL AND @Seats < @booked
        BEGIN
            SET @Problem = CONVERT(nvarchar(10), @booked) + N' people are already booked onto this session, '
                         + N'so it cannot be cut to ' + CONVERT(nvarchar(10), @Seats) + N' places.';
            SELECT TOP (0) CAST(NULL AS int) AS DevSessionId; RETURN;
        END;
        UPDATE sel.DevSession SET SessionCode = @SessionCode, StartDate = @StartDate, EndDate = @EndDate,
               Seats = @Seats, Location = @Location, IsCancelled = @IsCancelled
        WHERE DevSessionId = @id;
    END;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.DevSession', @KeyText = @keyText, @ActionCode = N'SAVE',
                       @LoginName = @LoginName;
    SELECT DevSessionId = @id, SessionCode = @SessionCode;
END
GO
PRINT '  sel.usp_Idp_Session_Save          applied';
GO

/* =====================================================================================
   sel.usp_Idp_Board — the Overview tab
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Board
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @windowStart date, @windowEnd date;
    SELECT @cycleId = p.CycleId, @windowStart = s.StartDate, @windowEnd = s.EndDate
    FROM sel.CycleStage s JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That stage no longer exists.';
        SELECT TOP (0) CAST(NULL AS int) AS PeopleTotal; RETURN;
    END;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope
    SELECT cc.PersonnelNo FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @cycleId;

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    /* Per person: how many obligations are open, and how many of those are planned. */
    ;WITH per AS
    (
        SELECT s.PersonnelNo,
               OpenCount = (SELECT COUNT(*) FROM #obl o WHERE o.PersonnelNo = s.PersonnelNo AND o.IsMet = 0),
               PlannedCount = (SELECT COUNT(*) FROM #obl o
                               WHERE o.PersonnelNo = s.PersonnelNo AND o.IsMet = 0
                                 AND (EXISTS (SELECT 1 FROM sel.IdpItem i
                                              WHERE i.CycleId = @cycleId AND i.PersonnelNo = o.PersonnelNo
                                                AND i.DevEventId = o.DevEventId
                                                AND (i.DevSessionId IS NOT NULL OR i.PencilledDate IS NOT NULL))
                                   OR EXISTS (SELECT 1 FROM sel.IdpCoverage cv
                                              WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = o.PersonnelNo
                                                AND cv.DevEventId = o.DevEventId AND cv.Days > 0)))
        FROM #scope s
    ),
    st AS
    (
        SELECT p.PersonnelNo, p.OpenCount, p.PlannedCount,
               PlanState = sel.fn_IdpPlanState(@cycleId, p.PersonnelNo, p.OpenCount, p.PlannedCount),
               TargetDate = sel.fn_IdpTargetDate(@cycleId, p.PersonnelNo, @CycleStageId)
        FROM per p
    )
    /* 1 — the counts. */
    SELECT PeopleTotal = (SELECT COUNT(*) FROM #scope),
           NoPlan      = (SELECT COUNT(*) FROM st WHERE PlanState = N'NO_PLAN'),
           InProgress  = (SELECT COUNT(*) FROM st WHERE PlanState = N'IN_PROGRESS'),
           Complete    = (SELECT COUNT(*) FROM st WHERE PlanState = N'COMPLETE'),
           Approved    = (SELECT COUNT(*) FROM st WHERE PlanState = N'APPROVED'),
           /* An open plan past its target reads as overdue. */
           Overdue     = (SELECT COUNT(*) FROM st WHERE PlanState IN (N'NO_PLAN', N'IN_PROGRESS')
                            AND TargetDate IS NOT NULL AND TargetDate < @AsOf),
           ReadyToApprove = (SELECT COUNT(*) FROM st WHERE PlanState = N'COMPLETE'),
           WindowStart = @windowStart, WindowEnd = @windowEnd,
           DaysLeft = CASE WHEN @windowEnd IS NULL THEN NULL ELSE DATEDIFF(DAY, @AsOf, @windowEnd) END,
           StageState = sel.fn_StageState(@CycleStageId, @AsOf, @TestMode),
           CanWrite = CONVERT(bit, CASE WHEN sec.fn_IsReadOnlyUser(@LoginName) = 1 THEN 0
                           WHEN sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN' THEN 0
                           ELSE 1 END);

    /* 2 — by readiness level. */
    SELECT lv.LevelCode, lv.Name, lv.SortOrder,
           People = (SELECT COUNT(DISTINCT r.PersonnelNo) FROM sel.SuccessionPlanRow r
                     WHERE r.CycleId = @cycleId AND r.LevelCode = lv.LevelCode AND r.IsDropped = 0
                       AND r.PersonnelNo IN (SELECT PersonnelNo FROM #scope)),
           OpenItems = (SELECT COUNT(*) FROM #obl o
                        WHERE o.IsMet = 0 AND o.PersonnelNo IN
                              (SELECT r.PersonnelNo FROM sel.SuccessionPlanRow r
                               WHERE r.CycleId = @cycleId AND r.LevelCode = lv.LevelCode AND r.IsDropped = 0))
    FROM sel.CycleReadiness lv WHERE lv.CycleId = @cycleId ORDER BY lv.SortOrder;

    /* 3 — by organisation. */
    SELECT e.OrgCode, o.Name AS OrgName,
           People = COUNT(DISTINCT e.PersonnelNo),
           OpenItems = (SELECT COUNT(*) FROM #obl ob
                        JOIN sel.Employee e2 ON e2.PersonnelNo = ob.PersonnelNo
                        WHERE ob.IsMet = 0 AND e2.OrgCode = e.OrgCode)
    FROM #scope s
    JOIN sel.Employee e ON e.PersonnelNo = s.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    GROUP BY e.OrgCode, o.Name
    ORDER BY COUNT(DISTINCT e.PersonnelNo) DESC;

    /* 4 — by event, so bulk booking knows where the demand is. */
    SELECT o.DevEventId, o.EventCode, o.EventName, o.KindCode,
           PeopleOpen = COUNT(*),
           Booked = (SELECT COUNT(*) FROM sel.IdpItem i
                     WHERE i.CycleId = @cycleId AND i.DevEventId = o.DevEventId AND i.DevSessionId IS NOT NULL),
           Pencilled = (SELECT COUNT(*) FROM sel.IdpItem i
                        WHERE i.CycleId = @cycleId AND i.DevEventId = o.DevEventId
                          AND i.DevSessionId IS NULL AND i.PencilledDate IS NOT NULL),
           SessionCount = (SELECT COUNT(*) FROM sel.DevSession ds
                           WHERE ds.DevEventId = o.DevEventId AND ds.IsCancelled = 0)
    FROM #obl o WHERE o.IsMet = 0
    GROUP BY o.DevEventId, o.EventCode, o.EventName, o.KindCode
    ORDER BY COUNT(*) DESC;

    /* 5 — the Needs attention list. */
    ;WITH per AS
    (
        SELECT s.PersonnelNo,
               OpenCount = (SELECT COUNT(*) FROM #obl o WHERE o.PersonnelNo = s.PersonnelNo AND o.IsMet = 0),
               PlannedCount = (SELECT COUNT(*) FROM #obl o
                               WHERE o.PersonnelNo = s.PersonnelNo AND o.IsMet = 0
                                 AND (EXISTS (SELECT 1 FROM sel.IdpItem i
                                              WHERE i.CycleId = @cycleId AND i.PersonnelNo = o.PersonnelNo
                                                AND i.DevEventId = o.DevEventId
                                                AND (i.DevSessionId IS NOT NULL OR i.PencilledDate IS NOT NULL))
                                   OR EXISTS (SELECT 1 FROM sel.IdpCoverage cv
                                              WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = o.PersonnelNo
                                                AND cv.DevEventId = o.DevEventId AND cv.Days > 0)))
        FROM #scope s
    )
    SELECT TOP (50)
           p.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
           p.OpenCount, p.PlannedCount,
           PlanState = sel.fn_IdpPlanState(@cycleId, p.PersonnelNo, p.OpenCount, p.PlannedCount),
           TargetDate = sel.fn_IdpTargetDate(@cycleId, p.PersonnelNo, @CycleStageId),
           IsOverdue = CONVERT(bit, CASE WHEN sel.fn_IdpTargetDate(@cycleId, p.PersonnelNo, @CycleStageId) < @AsOf
                             AND sel.fn_IdpPlanState(@cycleId, p.PersonnelNo, p.OpenCount, p.PlannedCount)
                                 IN (N'NO_PLAN', N'IN_PROGRESS')
                            THEN 1 ELSE 0 END),
           /* A small progress bar on the person row. */
           ProgressPct = CASE WHEN p.OpenCount = 0 THEN 100
                              ELSE CAST(100.0 * p.PlannedCount / p.OpenCount AS decimal(9,1)) END,
           Reason = CASE WHEN p.PlannedCount = 0 AND p.OpenCount > 0 THEN N'Nothing planned yet'
                         WHEN sel.fn_IdpTargetDate(@cycleId, p.PersonnelNo, @CycleStageId) < @AsOf
                              THEN N'Past its target date'
                         ELSE CONVERT(nvarchar(10), p.OpenCount - p.PlannedCount) + N' still to plan' END
    FROM per p
    JOIN sel.Employee e ON e.PersonnelNo = p.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    WHERE sel.fn_IdpPlanState(@cycleId, p.PersonnelNo, p.OpenCount, p.PlannedCount) IN (N'NO_PLAN', N'IN_PROGRESS')
    ORDER BY CASE WHEN sel.fn_IdpTargetDate(@cycleId, p.PersonnelNo, @CycleStageId) < @AsOf THEN 0 ELSE 1 END,
             p.OpenCount - p.PlannedCount DESC, e.FullName;

    DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_Board                 applied';
GO

/* =====================================================================================
   sel.usp_Idp_Person — the By person tab: one person's whole plan
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Person
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30),
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    IF NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                   JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
                   WHERE cc.CycleId = @cycleId AND cc.PersonnelNo = @PersonnelNo)
    BEGIN
        SET @Problem = N'This person is not in this cycle''s cohort, or not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope VALUES (@PersonnelNo);

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    /* 1 — the person and the plan's state. */
    DECLARE @openCount int = (SELECT COUNT(*) FROM #obl WHERE IsMet = 0);
    DECLARE @plannedCount int = (SELECT COUNT(*) FROM #obl o WHERE o.IsMet = 0
        AND (EXISTS (SELECT 1 FROM sel.IdpItem i WHERE i.CycleId = @cycleId AND i.PersonnelNo = @PersonnelNo
                       AND i.DevEventId = o.DevEventId AND (i.DevSessionId IS NOT NULL OR i.PencilledDate IS NOT NULL))
          OR EXISTS (SELECT 1 FROM sel.IdpCoverage cv WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = @PersonnelNo
                       AND cv.DevEventId = o.DevEventId AND cv.Days > 0)));

    SELECT e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle, e.GradeCode,
           OpenCount = @openCount, PlannedCount = @plannedCount,
           MetCount = (SELECT COUNT(*) FROM #obl WHERE IsMet = 1),
           PlanState = sel.fn_IdpPlanState(@cycleId, @PersonnelNo, @openCount, @plannedCount),
           TargetDate = sel.fn_IdpTargetDate(@cycleId, @PersonnelNo, @CycleStageId),
           TargetIsOverridden = CASE WHEN EXISTS (SELECT 1 FROM sel.IdpTarget t
                                                  WHERE t.CycleId = @cycleId AND t.PersonnelNo = @PersonnelNo
                                                    AND t.TargetDate IS NOT NULL) THEN 1 ELSE 0 END,
           IsOverdue = CONVERT(bit, CASE WHEN sel.fn_IdpTargetDate(@cycleId, @PersonnelNo, @CycleStageId) < @AsOf
                             AND @plannedCount < @openCount THEN 1 ELSE 0 END),
           LevelCode = (SELECT TOP (1) r.LevelCode FROM sel.SuccessionPlanRow r
                        WHERE r.CycleId = @cycleId AND r.PersonnelNo = @PersonnelNo AND r.IsDropped = 0
                        ORDER BY r.DecidedOnUtc DESC),
           ApprovedByLogin = (SELECT ApprovedByLogin FROM sel.IdpApproval a
                              WHERE a.CycleId = @cycleId AND a.PersonnelNo = @PersonnelNo),
           ApprovedOnUtc   = (SELECT ApprovedOnUtc FROM sel.IdpApproval a
                              WHERE a.CycleId = @cycleId AND a.PersonnelNo = @PersonnelNo),
           CanWrite = CONVERT(bit, CASE WHEN sec.fn_IsReadOnlyUser(@LoginName) = 1 THEN 0
                           WHEN sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN' THEN 0
                           ELSE 1 END)
    FROM sel.Employee e LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    WHERE e.PersonnelNo = @PersonnelNo;

    /* 2 — every requirement, met ones included but marked, so the plan reads whole.
       Two requirements with the same name from different sources show their item code. */
    SELECT ob.DevEventId, ob.ItemCode, ob.EventCode, ob.EventName, ob.KindCode,
           ob.IsMust, ob.IsMet, ob.Why, ob.Sources, ob.LevelNo,
           /* Show the code when the name is not unique in this plan. */
           NameIsAmbiguous = CASE WHEN (SELECT COUNT(*) FROM #obl o2 WHERE o2.EventName = ob.EventName) > 1
                                  THEN 1 ELSE 0 END,
           i.IdpItemId, i.DevSessionId, i.PencilledDate,
           StatusCode = sv.ValueCode, StatusName = sv.Name, StatusRole = sv.SemanticRole,
           SessionCode = ds.SessionCode, SessionStart = ds.StartDate, SessionEnd = ds.EndDate,
           SessionLocation = ds.Location,
           CoverageDays = (SELECT SUM(cv.Days) FROM sel.IdpCoverage cv
                           WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = @PersonnelNo
                             AND cv.DevEventId = ob.DevEventId),
           SessionCount = (SELECT COUNT(*) FROM sel.DevSession d2
                           WHERE d2.DevEventId = ob.DevEventId AND d2.IsCancelled = 0),
           RuleShort = sel.fn_EventRuleShort(ob.DevEventId)
    FROM #obl ob
    LEFT JOIN sel.IdpItem i ON i.CycleId = @cycleId AND i.PersonnelNo = @PersonnelNo AND i.DevEventId = ob.DevEventId
    LEFT JOIN cfg.DomainValue sv ON sv.DomainValueId = i.StatusValueId
    LEFT JOIN sel.DevSession ds ON ds.DevSessionId = i.DevSessionId
    /* Met ones are included and greyed, and they sort after the open ones. */
    ORDER BY ob.IsMet, ob.IsMust DESC, ob.EventCode;

    /* 3 — the session options for each open requirement, with seats left.  The last
       option in the dropdown is "pencil in a date", which the view adds. */
    SELECT ds.DevSessionId, ds.DevEventId, ds.SessionCode, ds.StartDate, ds.EndDate,
           ds.Seats, ds.Location,
           Booked = (SELECT COUNT(*) FROM sel.IdpItem i WHERE i.DevSessionId = ds.DevSessionId),
           SeatsLeft = CASE WHEN ds.Seats IS NULL THEN NULL
                            ELSE ds.Seats - (SELECT COUNT(*) FROM sel.IdpItem i WHERE i.DevSessionId = ds.DevSessionId) END,
           /* A session after the target date is offered, but flagged. */
           IsAfterTarget = CONVERT(bit, CASE WHEN ds.StartDate > sel.fn_IdpTargetDate(@cycleId, @PersonnelNo, @CycleStageId)
                                THEN 1 ELSE 0 END)
    FROM sel.DevSession ds
    WHERE ds.IsCancelled = 0
      AND ds.DevEventId IN (SELECT DevEventId FROM #obl WHERE IsMet = 0)
    ORDER BY ds.DevEventId, ISNULL(ds.StartDate, '9999-12-31');

    /* 4 — the coverage rows. */
    SELECT cv.IdpCoverageId, cv.DevEventId, cv.Department, cv.PositionCode,
           cv.IncumbentPersonnelNo, cv.StartDate, cv.EndDate, cv.Days, cv.ActorLogin, cv.AddedOnUtc,
           IncumbentName = (SELECT FullName FROM sel.Employee ie WHERE ie.PersonnelNo = cv.IncumbentPersonnelNo),
           EventName = (SELECT Name FROM sel.DevEvent de WHERE de.DevEventId = cv.DevEventId)
    FROM sel.IdpCoverage cv
    WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = @PersonnelNo
    ORDER BY cv.StartDate;

    /* 5 — notes. */
    SELECT IdpNoteId, NoteText, ActorLogin, AddedOnUtc
    FROM sel.IdpNote WHERE CycleId = @cycleId AND PersonnelNo = @PersonnelNo
    ORDER BY AddedOnUtc DESC;

    DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_Person                applied';
GO

/* sel.usp_Idp_Requirements — the open obligations across the cohort, one row per
   person x event, deduplicated when two sources name the same event.                 */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Requirements
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @DevEventId   int = NULL,
    @Search       nvarchar(200) = NULL,
    @OpenOnly     bit = 1,
    @AsOf         date = NULL,
    @PageNo       int = 1,
    @PageSize     int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageNo IS NULL OR @PageNo < 1 SET @PageNo = 1;

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope
    SELECT cc.PersonnelNo FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @cycleId;

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    SELECT ob.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
           ob.DevEventId, ob.ItemCode, ob.EventCode, ob.EventName, ob.KindCode,
           ob.IsMust, ob.IsMet, ob.Why, ob.Sources,
           i.IdpItemId, i.DevSessionId, i.PencilledDate,
           StatusCode = ISNULL(sv.ValueCode, N'OPEN'),
           SessionCode = ds.SessionCode, SessionStart = ds.StartDate,
           CoverageDays = (SELECT SUM(cv.Days) FROM sel.IdpCoverage cv
                           WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = ob.PersonnelNo
                             AND cv.DevEventId = ob.DevEventId)
    FROM #obl ob
    JOIN sel.Employee e ON e.PersonnelNo = ob.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    LEFT JOIN sel.IdpItem i ON i.CycleId = @cycleId AND i.PersonnelNo = ob.PersonnelNo AND i.DevEventId = ob.DevEventId
    LEFT JOIN cfg.DomainValue sv ON sv.DomainValueId = i.StatusValueId
    LEFT JOIN sel.DevSession ds ON ds.DevSessionId = i.DevSessionId
    WHERE (@OpenOnly = 0 OR ob.IsMet = 0)
      AND (@DevEventId IS NULL OR ob.DevEventId = @DevEventId)
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
           OR ob.PersonnelNo LIKE N'%' + @Search + N'%' OR ob.EventName LIKE N'%' + @Search + N'%')
    ORDER BY ob.EventCode, e.FullName
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT TotalRows = COUNT(*)
    FROM #obl ob JOIN sel.Employee e ON e.PersonnelNo = ob.PersonnelNo
    WHERE (@OpenOnly = 0 OR ob.IsMet = 0)
      AND (@DevEventId IS NULL OR ob.DevEventId = @DevEventId)
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%'
           OR ob.PersonnelNo LIKE N'%' + @Search + N'%' OR ob.EventName LIKE N'%' + @Search + N'%');

    DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_Requirements          applied';
GO


/* =====================================================================================
   12_idp.sql, continued  —  booking, pencilling, coverage, conflicts and approval
   ===================================================================================== */

PRINT '';
PRINT '== 12_idp (part 2) ===================================================';
GO

/* sel.usp_Idp_BookMany — book people onto one session.  Seats are respected, and an
   over-booking is refused with a sentence naming how many places are left.
   The single-person form is this with one row in the list.                            */
CREATE OR ALTER PROCEDURE sel.usp_Idp_BookMany
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @DevSessionId int,
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

    DECLARE @cycleId int, @screenCode nvarchar(160);
    SELECT @cycleId = p.CycleId, @screenCode = sk.ScreenCode
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That stage no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    /* Read only outside the stage window unless test mode. */
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1 OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so nothing can be booked.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    DECLARE @eventId int, @seats int, @cancelled bit, @sessionCode nvarchar(60);
    SELECT @eventId = DevEventId, @seats = Seats, @cancelled = IsCancelled, @sessionCode = SessionCode
    FROM sel.DevSession WHERE DevSessionId = @DevSessionId;

    IF @eventId IS NULL
    BEGIN
        SET @Problem = N'That session no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF @cancelled = 1
    BEGIN
        SET @Problem = N'Session ' + @sessionCode + N' has been cancelled, so nobody can be booked onto it.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    /* Only people in this cohort, in this viewer's organisations, not already booked here. */
    CREATE TABLE #book (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY, OrgCode nvarchar(40) NULL);
    INSERT #book (PersonnelNo, OrgCode)
    SELECT cc.PersonnelNo, cc.OrgCode
    FROM @People p
    JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = p.Id
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE NOT EXISTS (SELECT 1 FROM sel.IdpItem i
                      WHERE i.CycleId = @cycleId AND i.PersonnelNo = cc.PersonnelNo
                        AND i.DevEventId = @eventId AND i.DevSessionId = @DevSessionId);

    DECLARE @asked int = (SELECT COUNT(*) FROM #book);
    IF @asked = 0
    BEGIN
        SET @Problem = N'Nobody new was selected: they are already booked onto this session, or outside your organisations.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        DROP TABLE #book; RETURN;
    END;

    /* Seats.  The refusal names how many places are left. */
    IF @seats IS NOT NULL
    BEGIN
        DECLARE @taken int = (SELECT COUNT(*) FROM sel.IdpItem WHERE DevSessionId = @DevSessionId);
        DECLARE @left int = @seats - @taken;
        IF @asked > @left
        BEGIN
            SET @Problem = REPLACE(REPLACE(REPLACE(cfg.fn_Message(N'SEATS_LEFT'),
                               N'{left}',  CONVERT(nvarchar(10), @left)),
                               N'{s}',     CASE WHEN @left = 1 THEN N'' ELSE N's' END),
                               N'{asked}', CONVERT(nvarchar(10), @asked));
            SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
            DROP TABLE #book; RETURN;
        END;
    END;

    BEGIN TRAN;
    MERGE sel.IdpItem AS t
    USING (SELECT PersonnelNo, OrgCode FROM #book) AS s
       ON t.CycleId = @cycleId AND t.PersonnelNo = s.PersonnelNo AND t.DevEventId = @eventId
    WHEN MATCHED THEN
        UPDATE SET DevSessionId = @DevSessionId, PencilledDate = NULL,
                   StatusValueId = cfg.fn_DomainValueId(N'IDP_STATUS', N'BOOKED'),
                   ActorLogin = @LoginName, ChangedOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CycleId, PersonnelNo, DevEventId, DevSessionId, StatusValueId, SourceValueId, OrgCode, ActorLogin)
        VALUES (@cycleId, s.PersonnelNo, @eventId, @DevSessionId,
                cfg.fn_DomainValueId(N'IDP_STATUS', N'BOOKED'),
                cfg.fn_DomainValueId(N'IDP_SOURCE', N'LEVEL'), s.OrgCode, @LoginName);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevSessionId) + N'/' + CONVERT(nvarchar(10), @asked) + N' people';
    EXEC audit.usp_Log @TableName = N'sel.IdpItem', @KeyText = @keyText, @ActionCode = N'BOOK',
                       @LoginName = @LoginName;

    SELECT b.PersonnelNo, e.FullName, SessionCode = @sessionCode, DevSessionId = @DevSessionId,
           SeatsLeft = CASE WHEN @seats IS NULL THEN NULL
                            ELSE @seats - (SELECT COUNT(*) FROM sel.IdpItem WHERE DevSessionId = @DevSessionId) END
    FROM #book b JOIN sel.Employee e ON e.PersonnelNo = b.PersonnelNo;

    DROP TABLE #book;
END
GO
PRINT '  sel.usp_Idp_BookMany              applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Idp_Book
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @DevSessionId int,
    @PersonnelNo  nvarchar(30),
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @one dbo.IdList;
    INSERT @one (Id) VALUES (@PersonnelNo);
    EXEC sel.usp_Idp_BookMany @LoginName = @LoginName, @CycleStageId = @CycleStageId,
         @DevSessionId = @DevSessionId, @People = @one, @AsOf = @AsOf,
         @TestMode = @TestMode, @Problem = @Problem OUTPUT;
END
GO
PRINT '  sel.usp_Idp_Book                  applied';
GO

/* sel.usp_Idp_PencilMany — "pencil in a date" where no session exists. */
CREATE OR ALTER PROCEDURE sel.usp_Idp_PencilMany
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @DevEventId   int,
    @PencilledDate date,
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

    DECLARE @cycleId int, @screenCode nvarchar(160);
    SELECT @cycleId = p.CycleId, @screenCode = sk.ScreenCode
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
       OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so no date can be pencilled in.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF @PencilledDate IS NULL
    BEGIN
        SET @Problem = N'Pencilling one in needs a date.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    BEGIN TRAN;
    MERGE sel.IdpItem AS t
    USING (SELECT cc.PersonnelNo, cc.OrgCode
           FROM @People p
           JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = p.Id
           JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode) AS s
       ON t.CycleId = @cycleId AND t.PersonnelNo = s.PersonnelNo AND t.DevEventId = @DevEventId
    WHEN MATCHED THEN
        UPDATE SET DevSessionId = NULL, PencilledDate = @PencilledDate,
                   StatusValueId = cfg.fn_DomainValueId(N'IDP_STATUS', N'PENCILLED'),
                   ActorLogin = @LoginName, ChangedOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CycleId, PersonnelNo, DevEventId, PencilledDate, StatusValueId, SourceValueId, OrgCode, ActorLogin)
        VALUES (@cycleId, s.PersonnelNo, @DevEventId, @PencilledDate,
                cfg.fn_DomainValueId(N'IDP_STATUS', N'PENCILLED'),
                cfg.fn_DomainValueId(N'IDP_SOURCE', N'LEVEL'), s.OrgCode, @LoginName);
    DECLARE @n int = @@ROWCOUNT;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @DevEventId) + N'/' + CONVERT(nvarchar(10), @n) + N' people';
    EXEC audit.usp_Log @TableName = N'sel.IdpItem', @KeyText = @keyText, @ActionCode = N'PENCIL',
                       @LoginName = @LoginName;

    SELECT PersonnelNo = p.Id, PencilledDate = @PencilledDate, DevEventId = @DevEventId
    FROM @People p;
END
GO
PRINT '  sel.usp_Idp_PencilMany            applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Idp_Pencil
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @DevEventId   int,
    @PersonnelNo  nvarchar(30),
    @PencilledDate date,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @one dbo.IdList;
    INSERT @one (Id) VALUES (@PersonnelNo);
    EXEC sel.usp_Idp_PencilMany @LoginName = @LoginName, @CycleStageId = @CycleStageId,
         @DevEventId = @DevEventId, @PencilledDate = @PencilledDate, @People = @one,
         @AsOf = @AsOf, @TestMode = @TestMode, @Problem = @Problem OUTPUT;
END
GO
PRINT '  sel.usp_Idp_Pencil                applied';
GO

/* =====================================================================================
   sel.usp_Idp_Suggest — the one-click plan
   -------------------------------------------------------------------------------------
   Books every open requirement onto the EARLIEST session with a free seat that falls
   inside the target date; leaves a pencilled date where no session exists; and NEVER
   assigns coverage, because coverage costs leave and is a human decision.
   It returns what it did as a list of sentences.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Suggest
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30) = NULL,   -- NULL means every remaining plan
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @screenCode nvarchar(160);
    SELECT @cycleId = p.CycleId, @screenCode = sk.ScreenCode
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
       OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS nvarchar(600)) AS Sentence; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so nothing can be planned.';
        SELECT TOP (0) CAST(NULL AS nvarchar(600)) AS Sentence; RETURN;
    END;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope
    SELECT cc.PersonnelNo FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @cycleId AND (@PersonnelNo IS NULL OR cc.PersonnelNo = @PersonnelNo);

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    /* What still needs planning, with each person's target date. */
    CREATE TABLE #todo
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        TargetDate date NULL, OrgCode nvarchar(40) NULL,
        PRIMARY KEY (PersonnelNo, DevEventId)
    );
    INSERT #todo (PersonnelNo, DevEventId, EventCode, EventName, KindCode, TargetDate, OrgCode)
    SELECT o.PersonnelNo, o.DevEventId, o.EventCode, o.EventName, o.KindCode,
           sel.fn_IdpTargetDate(@cycleId, o.PersonnelNo, @CycleStageId),
           (SELECT OrgCode FROM sel.CycleCandidate cc WHERE cc.CycleId = @cycleId AND cc.PersonnelNo = o.PersonnelNo)
    FROM #obl o
    WHERE o.IsMet = 0
      AND NOT EXISTS (SELECT 1 FROM sel.IdpItem i
                      WHERE i.CycleId = @cycleId AND i.PersonnelNo = o.PersonnelNo
                        AND i.DevEventId = o.DevEventId
                        AND (i.DevSessionId IS NOT NULL OR i.PencilledDate IS NOT NULL))
      AND NOT EXISTS (SELECT 1 FROM sel.IdpCoverage cv
                      WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = o.PersonnelNo
                        AND cv.DevEventId = o.DevEventId AND cv.Days > 0);

    CREATE TABLE #did (Sentence nvarchar(600) NOT NULL, SortOrder int NOT NULL IDENTITY(1,1));

    /* Seat counts are consumed as we go, so a large cohort cannot over-book a session.
       This walks the to-do list one row at a time on purpose: a set-based booking would
       hand the same last seat to several people at once. */
    DECLARE @person nvarchar(30), @event int, @eventName nvarchar(300), @target date,
            @org nvarchar(40), @kind nvarchar(30);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PersonnelNo, DevEventId, EventName, TargetDate, OrgCode, KindCode
        FROM #todo ORDER BY TargetDate, PersonnelNo, DevEventId;

    OPEN cur; FETCH NEXT FROM cur INTO @person, @event, @eventName, @target, @org, @kind;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* Coverage is never auto-assigned.  A summed obligation is left for a human. */
        IF (SELECT EvalModeCode FROM sel.RequirementKind WHERE KindCode = @kind) = N'SUM'
        BEGIN
            INSERT #did (Sentence)
            VALUES (N'Left "' + @eventName + N'" for ' + @person
                  + N' — ' + cfg.fn_Message(N'IDP_COVERAGE_MANUAL'));
        END
        ELSE
        BEGIN
            /* The earliest session with a free seat that falls inside the target date. */
            DECLARE @sessionId int = NULL, @sessionCode nvarchar(60), @start date;
            SELECT TOP (1) @sessionId = ds.DevSessionId, @sessionCode = ds.SessionCode, @start = ds.StartDate
            FROM sel.DevSession ds
            WHERE ds.DevEventId = @event AND ds.IsCancelled = 0
              AND (ds.Seats IS NULL
                   OR ds.Seats > (SELECT COUNT(*) FROM sel.IdpItem i WHERE i.DevSessionId = ds.DevSessionId))
              AND (@target IS NULL OR ds.StartDate IS NULL OR ds.StartDate <= @target)
              AND (ds.StartDate IS NULL OR ds.StartDate >= @AsOf)
            ORDER BY ISNULL(ds.StartDate, '9999-12-31'), ds.DevSessionId;

            IF @sessionId IS NOT NULL
            BEGIN
                MERGE sel.IdpItem AS t
                USING (SELECT @person AS PersonnelNo) AS s
                   ON t.CycleId = @cycleId AND t.PersonnelNo = s.PersonnelNo AND t.DevEventId = @event
                WHEN MATCHED THEN
                    UPDATE SET DevSessionId = @sessionId, PencilledDate = NULL,
                               StatusValueId = cfg.fn_DomainValueId(N'IDP_STATUS', N'BOOKED'),
                               ActorLogin = @LoginName, ChangedOnUtc = SYSUTCDATETIME()
                WHEN NOT MATCHED BY TARGET THEN
                    INSERT (CycleId, PersonnelNo, DevEventId, DevSessionId, StatusValueId, SourceValueId, OrgCode, ActorLogin)
                    VALUES (@cycleId, @person, @event, @sessionId,
                            cfg.fn_DomainValueId(N'IDP_STATUS', N'BOOKED'),
                            cfg.fn_DomainValueId(N'IDP_SOURCE', N'LEVEL'), @org, @LoginName);

                INSERT #did (Sentence)
                VALUES (N'Booked ' + @person + N' onto ' + @sessionCode + N' for "' + @eventName + N'"'
                      + ISNULL(N' on ' + CONVERT(nvarchar(10), @start, 23), N''));
            END
            ELSE
            BEGIN
                /* No session exists, so leave a pencilled date on the target. */
                DECLARE @pencil date = ISNULL(@target, DATEADD(MONTH, 6, @AsOf));
                MERGE sel.IdpItem AS t
                USING (SELECT @person AS PersonnelNo) AS s
                   ON t.CycleId = @cycleId AND t.PersonnelNo = s.PersonnelNo AND t.DevEventId = @event
                WHEN MATCHED THEN
                    UPDATE SET DevSessionId = NULL, PencilledDate = @pencil,
                               StatusValueId = cfg.fn_DomainValueId(N'IDP_STATUS', N'PENCILLED'),
                               ActorLogin = @LoginName, ChangedOnUtc = SYSUTCDATETIME()
                WHEN NOT MATCHED BY TARGET THEN
                    INSERT (CycleId, PersonnelNo, DevEventId, PencilledDate, StatusValueId, SourceValueId, OrgCode, ActorLogin)
                    VALUES (@cycleId, @person, @event, @pencil,
                            cfg.fn_DomainValueId(N'IDP_STATUS', N'PENCILLED'),
                            cfg.fn_DomainValueId(N'IDP_SOURCE', N'LEVEL'), @org, @LoginName);

                INSERT #did (Sentence)
                VALUES (N'Pencilled ' + @person + N' in for "' + @eventName + N'" on '
                      + CONVERT(nvarchar(10), @pencil, 23) + N' — no session is scheduled.');
            END;
        END;

        FETCH NEXT FROM cur INTO @person, @event, @eventName, @target, @org, @kind;
    END;
    CLOSE cur; DEALLOCATE cur;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @cycleId) + N'/' + ISNULL(@PersonnelNo, N'cohort');
    EXEC audit.usp_Log @TableName = N'sel.IdpItem', @KeyText = @keyText, @ActionCode = N'SUGGEST',
                       @LoginName = @LoginName;

    /* What it did, as a list of sentences. */
    SELECT Sentence, SortOrder FROM #did ORDER BY SortOrder;
    SELECT Changed = (SELECT COUNT(*) FROM #did);

    DROP TABLE #did; DROP TABLE #todo; DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_Suggest               applied';
GO

/* =====================================================================================
   Coverage — an acting assignment.  The day count is computed here, and the person's
   remaining coverage balance is deducted and persisted.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Coverage_Add
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30),
    @DevEventId   int = NULL,
    @Department   nvarchar(200) = NULL,
    @PositionCode nvarchar(60) = NULL,
    @IncumbentPersonnelNo nvarchar(30) = NULL,
    @StartDate    date,
    @EndDate      date,
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int, @screenCode nvarchar(160);
    SELECT @cycleId = p.CycleId, @screenCode = sk.ScreenCode
    FROM sel.CycleStage s
    JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
    JOIN sel.StageKind sk ON sk.StageKindCode = s.StageKindCode
    WHERE s.CycleStageId = @CycleStageId;

    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
       OR sec.fn_ScreenAccess(@LoginName, @screenCode) < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so coverage cannot be assigned.';
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;
    IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
    BEGIN
        SET @Problem = N'Coverage needs a start and an end date, and it cannot end before it starts.';
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;

    DECLARE @org nvarchar(40) = (SELECT OrgCode FROM sel.CycleCandidate
                                 WHERE CycleId = @cycleId AND PersonnelNo = @PersonnelNo);
    IF @org IS NULL OR NOT EXISTS (SELECT 1 FROM sec.fn_UserOrgScope(@LoginName) sc WHERE sc.OrgCode = @org)
    BEGIN
        SET @Problem = N'This person is not in this cycle''s cohort, or not in an organisation you have been granted.';
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;

    /* The day count is computed in SQL, inclusive of both ends. */
    DECLARE @days int = DATEDIFF(DAY, @StartDate, @EndDate) + 1;

    BEGIN TRAN;
    INSERT sel.IdpCoverage (CycleId, PersonnelNo, DevEventId, Department, PositionCode,
                            IncumbentPersonnelNo, StartDate, EndDate, Days, OrgCode, ActorLogin)
    VALUES (@cycleId, @PersonnelNo, @DevEventId, @Department, @PositionCode,
            @IncumbentPersonnelNo, @StartDate, @EndDate, @days, @org, @LoginName);
    DECLARE @id bigint = SCOPE_IDENTITY();

    /* The balance is deducted and persisted, so it survives the request. */
    MERGE sel.EmployeeMetric AS t
    USING (SELECT @PersonnelNo AS PersonnelNo) AS s
       ON t.PersonnelNo = s.PersonnelNo AND t.MetricKey = N'CoverageDaysPlanned'
    WHEN MATCHED THEN UPDATE SET NumValue = ISNULL(t.NumValue, 0) + @days, RefreshedUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (PersonnelNo, MetricKey, NumValue, AsOfDate) VALUES (s.PersonnelNo, N'CoverageDaysPlanned', @days, @AsOf);
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @id);
    EXEC audit.usp_Log @TableName = N'sel.IdpCoverage', @KeyText = @keyText, @ActionCode = N'ADD',
                       @LoginName = @LoginName;

    SELECT IdpCoverageId = @id, PersonnelNo = @PersonnelNo, Days = @days,
           StartDate = @StartDate, EndDate = @EndDate,
           BalanceDays = (SELECT NumValue FROM sel.EmployeeMetric
                          WHERE PersonnelNo = @PersonnelNo AND MetricKey = N'CoverageDaysPlanned');
END
GO
PRINT '  sel.usp_Idp_Coverage_Add          applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Idp_Coverage_Remove
    @LoginName     nvarchar(128),
    @IdpCoverageId bigint,
    @Problem       nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    DECLARE @cycleId int, @person nvarchar(30), @days int;
    SELECT @cycleId = CycleId, @person = PersonnelNo, @days = Days
    FROM sel.IdpCoverage WHERE IdpCoverageId = @IdpCoverageId;

    IF @cycleId IS NULL
    BEGIN
        SET @Problem = N'That coverage assignment no longer exists.';
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;
    IF sec.fn_IsReadOnlyUser(@LoginName) = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;
    IF sel.fn_CycleStatusCode(@cycleId) = N'CLOSED'
    BEGIN
        SET @Problem = cfg.fn_Message(N'CLOSED_CYCLE');
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpCoverageId; RETURN;
    END;

    BEGIN TRAN;
    DELETE FROM sel.IdpCoverage WHERE IdpCoverageId = @IdpCoverageId;
    /* Give the days back. */
    UPDATE sel.EmployeeMetric SET NumValue = ISNULL(NumValue, 0) - @days, RefreshedUtc = SYSUTCDATETIME()
    WHERE PersonnelNo = @person AND MetricKey = N'CoverageDaysPlanned';
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @IdpCoverageId);
    EXEC audit.usp_Log @TableName = N'sel.IdpCoverage', @KeyText = @keyText, @ActionCode = N'REMOVE',
                       @LoginName = @LoginName;

    SELECT IdpCoverageId = @IdpCoverageId, Removed = CAST(1 AS bit), DaysReturned = @days;
END
GO
PRINT '  sel.usp_Idp_Coverage_Remove       applied';
GO

/* sel.usp_Idp_Coverage_Board — the Coverage tab: the incumbent's demand and the
   successors available.                                                              */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Coverage_Board
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @Search       nvarchar(200) = NULL,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    /* The assignments already made. */
    SELECT cv.IdpCoverageId, cv.PersonnelNo, e.FullName, cv.Department, cv.PositionCode,
           cv.IncumbentPersonnelNo, cv.StartDate, cv.EndDate, cv.Days, cv.ActorLogin, cv.AddedOnUtc,
           IncumbentName = (SELECT FullName FROM sel.Employee ie WHERE ie.PersonnelNo = cv.IncumbentPersonnelNo),
           EventName = (SELECT Name FROM sel.DevEvent de WHERE de.DevEventId = cv.DevEventId),
           OrgName = o.Name
    FROM sel.IdpCoverage cv
    JOIN sel.Employee e ON e.PersonnelNo = cv.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cv.OrgCode
    LEFT JOIN sel.OrgNode o ON o.OrgCode = cv.OrgCode
    WHERE cv.CycleId = @cycleId
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%' OR cv.Department LIKE N'%' + @Search + N'%')
    ORDER BY cv.StartDate, e.FullName;

    /* The successors available: people in the cohort with a summed obligation still open. */
    SELECT e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
           DaysPlanned = ISNULL((SELECT SUM(cv.Days) FROM sel.IdpCoverage cv
                                 WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = e.PersonnelNo), 0),
           DaysRecorded = ISNULL((SELECT NumValue FROM sel.EmployeeMetric m
                                  WHERE m.PersonnelNo = e.PersonnelNo AND m.MetricKey = N'DaysCovered'), 0)
    FROM sel.CycleCandidate cc
    JOIN sel.Employee e ON e.PersonnelNo = cc.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    LEFT JOIN sel.OrgNode o ON o.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @cycleId
      AND (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%')
    ORDER BY e.FullName;
END
GO
PRINT '  sel.usp_Idp_Coverage_Board        applied';
GO

/* sel.usp_Idp_Conflicts — overlapping bookings, coverage overlapping a booking, and a
   person covering an incumbent on days they are booked away.                          */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Conflicts
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30) = NULL,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    /* 1 — two bookings whose sessions overlap. */
    SELECT ConflictKind = N'BOOKING_OVERLAP',
           a.PersonnelNo, e.FullName,
           FirstWhat = ea.Name, FirstFrom = sa.StartDate, FirstTo = sa.EndDate,
           SecondWhat = eb.Name, SecondFrom = sb.StartDate, SecondTo = sb.EndDate,
           Sentence = e.FullName + N' is booked on "' + ea.Name + N'" and "' + eb.Name
                    + N'" over the same days.'
    FROM sel.IdpItem a
    JOIN sel.IdpItem b ON b.CycleId = a.CycleId AND b.PersonnelNo = a.PersonnelNo AND b.IdpItemId > a.IdpItemId
    JOIN sel.DevSession sa ON sa.DevSessionId = a.DevSessionId
    JOIN sel.DevSession sb ON sb.DevSessionId = b.DevSessionId
    JOIN sel.DevEvent ea ON ea.DevEventId = a.DevEventId
    JOIN sel.DevEvent eb ON eb.DevEventId = b.DevEventId
    JOIN sel.Employee e ON e.PersonnelNo = a.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = a.OrgCode
    WHERE a.CycleId = @cycleId
      AND (@PersonnelNo IS NULL OR a.PersonnelNo = @PersonnelNo)
      AND sa.StartDate IS NOT NULL AND sb.StartDate IS NOT NULL
      AND sa.StartDate <= ISNULL(sb.EndDate, sb.StartDate)
      AND sb.StartDate <= ISNULL(sa.EndDate, sa.StartDate)

    UNION ALL

    /* 2 — coverage overlapping a booking: they are away on days they are covering. */
    SELECT N'COVERAGE_OVERLAPS_BOOKING',
           cv.PersonnelNo, e.FullName,
           N'Covering ' + ISNULL(cv.Department, N'a department'), cv.StartDate, cv.EndDate,
           ev.Name, ds.StartDate, ds.EndDate,
           e.FullName + N' is covering ' + ISNULL(cv.Department, N'a department')
             + N' on days they are booked onto "' + ev.Name + N'".'
    FROM sel.IdpCoverage cv
    JOIN sel.IdpItem i ON i.CycleId = cv.CycleId AND i.PersonnelNo = cv.PersonnelNo
    JOIN sel.DevSession ds ON ds.DevSessionId = i.DevSessionId
    JOIN sel.DevEvent ev ON ev.DevEventId = i.DevEventId
    JOIN sel.Employee e ON e.PersonnelNo = cv.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cv.OrgCode
    WHERE cv.CycleId = @cycleId
      AND (@PersonnelNo IS NULL OR cv.PersonnelNo = @PersonnelNo)
      AND ds.StartDate IS NOT NULL
      AND cv.StartDate <= ISNULL(ds.EndDate, ds.StartDate)
      AND ds.StartDate <= cv.EndDate

    UNION ALL

    /* 3 — two coverage spells over the same days. */
    SELECT N'COVERAGE_OVERLAP',
           a.PersonnelNo, e.FullName,
           ISNULL(a.Department, N'a department'), a.StartDate, a.EndDate,
           ISNULL(b.Department, N'a department'), b.StartDate, b.EndDate,
           e.FullName + N' is assigned to cover two places over the same days.'
    FROM sel.IdpCoverage a
    JOIN sel.IdpCoverage b ON b.CycleId = a.CycleId AND b.PersonnelNo = a.PersonnelNo
                          AND b.IdpCoverageId > a.IdpCoverageId
    JOIN sel.Employee e ON e.PersonnelNo = a.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = a.OrgCode
    WHERE a.CycleId = @cycleId
      AND (@PersonnelNo IS NULL OR a.PersonnelNo = @PersonnelNo)
      AND a.StartDate <= b.EndDate AND b.StartDate <= a.EndDate
    ORDER BY 2, 1;
END
GO
PRINT '  sel.usp_Idp_Conflicts             applied';
GO

/* sel.usp_Idp_Target_Save / sel.usp_Idp_Note_Add */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Target_Save
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30),
    @TargetDate   date = NULL,        -- NULL clears the override and goes back to derived
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);
    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS date) AS TargetDate; RETURN;
    END;

    MERGE sel.IdpTarget AS t
    USING (SELECT @cycleId AS CycleId, @PersonnelNo AS PersonnelNo) AS s
       ON t.CycleId = s.CycleId AND t.PersonnelNo = s.PersonnelNo
    WHEN MATCHED THEN UPDATE SET TargetDate = @TargetDate, SetByLogin = @LoginName, SetOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CycleId, PersonnelNo, TargetDate, SetByLogin)
        VALUES (s.CycleId, s.PersonnelNo, @TargetDate, @LoginName);

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @cycleId) + N'/' + @PersonnelNo;
    EXEC audit.usp_Log @TableName = N'sel.IdpTarget', @KeyText = @keyText, @ActionCode = N'SAVE',
                       @LoginName = @LoginName;

    SELECT TargetDate = sel.fn_IdpTargetDate(@cycleId, @PersonnelNo, @CycleStageId),
           IsOverridden = CONVERT(bit, CASE WHEN @TargetDate IS NULL THEN 0 ELSE 1 END);
END
GO
PRINT '  sel.usp_Idp_Target_Save           applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Idp_Note_Add
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30),
    @NoteText     nvarchar(max),
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);
    IF @cycleId IS NULL OR sec.fn_IsReadOnlyUser(@LoginName) = 1
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpNoteId; RETURN;
    END;
    IF NULLIF(LTRIM(RTRIM(ISNULL(@NoteText, N''))), N'') IS NULL
    BEGIN
        SET @Problem = N'An empty note is not worth keeping.';
        SELECT TOP (0) CAST(NULL AS bigint) AS IdpNoteId; RETURN;
    END;

    INSERT sel.IdpNote (CycleId, PersonnelNo, NoteText, ActorLogin)
    VALUES (@cycleId, @PersonnelNo, @NoteText, @LoginName);

    SELECT IdpNoteId = SCOPE_IDENTITY(), NoteText = @NoteText, ActorLogin = @LoginName;
END
GO
PRINT '  sel.usp_Idp_Note_Add              applied';
GO

/* =====================================================================================
   Approval — at plan level, never per requirement
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Idp_ApproveMany
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
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;
    IF sel.fn_StageState(@CycleStageId, @AsOf, @TestMode) <> N'OPEN'
    BEGIN
        SET @Problem = N'This stage is not open, so nothing can be approved.';
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo; RETURN;
    END;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope
    SELECT cc.PersonnelNo FROM @People p
    JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = p.Id
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode;

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    /* Refuses unless every open requirement has a booking, a date, or coverage days. */
    CREATE TABLE #notready (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY, Outstanding int NOT NULL);
    INSERT #notready (PersonnelNo, Outstanding)
    SELECT s.PersonnelNo,
           (SELECT COUNT(*) FROM #obl o
            WHERE o.PersonnelNo = s.PersonnelNo AND o.IsMet = 0
              AND NOT EXISTS (SELECT 1 FROM sel.IdpItem i
                              WHERE i.CycleId = @cycleId AND i.PersonnelNo = o.PersonnelNo
                                AND i.DevEventId = o.DevEventId
                                AND (i.DevSessionId IS NOT NULL OR i.PencilledDate IS NOT NULL))
              AND NOT EXISTS (SELECT 1 FROM sel.IdpCoverage cv
                              WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = o.PersonnelNo
                                AND cv.DevEventId = o.DevEventId AND cv.Days > 0))
    FROM #scope s;

    DELETE FROM #scope WHERE PersonnelNo IN (SELECT PersonnelNo FROM #notready WHERE Outstanding > 0);

    DECLARE @blocked int = (SELECT COUNT(*) FROM #notready WHERE Outstanding > 0);
    DECLARE @ready int = (SELECT COUNT(*) FROM #scope);

    IF @ready = 0
    BEGIN
        SET @Problem = cfg.fn_Message(N'IDP_NOT_READY');
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        DROP TABLE #notready; DROP TABLE #obl; DROP TABLE #scope; RETURN;
    END;

    BEGIN TRAN;
    MERGE sel.IdpApproval AS t
    USING (SELECT s.PersonnelNo, cc.OrgCode FROM #scope s
           JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = s.PersonnelNo) AS src
       ON t.CycleId = @cycleId AND t.PersonnelNo = src.PersonnelNo
    WHEN MATCHED THEN UPDATE SET ApprovedByLogin = @LoginName, ApprovedOnUtc = SYSUTCDATETIME(),
                                 NotifiedOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (CycleId, PersonnelNo, ApprovedByLogin, NotifiedOnUtc, OrgCode)
        VALUES (@cycleId, src.PersonnelNo, @LoginName, SYSUTCDATETIME(), src.OrgCode);

    /* Approval is a decision, and lands in the decision log like every other one. */
    INSERT sel.CandidateDecision (CycleId, CycleProcessId, CycleStageId, PersonnelNo,
                                  DecisionValueId, Reason, PerformerLevelValueId, ActorLogin, IsTest, OrgCode)
    SELECT @cycleId, @processId, @CycleStageId, s.PersonnelNo,
           cfg.fn_DomainValueId(N'DECISION', N'PLAN_APPROVED'),
           N'Development plan approved and notified',
           @performerId, @LoginName, @TestMode, cc.OrgCode
    FROM #scope s
    JOIN sel.CycleCandidate cc ON cc.CycleId = @cycleId AND cc.PersonnelNo = s.PersonnelNo;
    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @cycleId) + N'/' + CONVERT(nvarchar(10), @ready) + N' plans';
    EXEC audit.usp_Log @TableName = N'sel.IdpApproval', @KeyText = @keyText, @ActionCode = N'APPROVE',
                       @LoginName = @LoginName;

    /* A partial success says so, rather than claiming everything landed. */
    IF @blocked > 0
        SET @Problem = CONVERT(nvarchar(10), @ready) + N' plan' + CASE WHEN @ready = 1 THEN N' was' ELSE N's were' END
                     + N' approved. ' + CONVERT(nvarchar(10), @blocked) + N' still ha'
                     + CASE WHEN @blocked = 1 THEN N's' ELSE N've' END
                     + N' requirements with no booking, date or coverage days.';

    SELECT s.PersonnelNo, e.FullName, ApprovedOnUtc = SYSUTCDATETIME(), ApprovedByLogin = @LoginName
    FROM #scope s JOIN sel.Employee e ON e.PersonnelNo = s.PersonnelNo;

    DROP TABLE #notready; DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_ApproveMany           applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Idp_Approve
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @PersonnelNo  nvarchar(30),
    @AsOf         date = NULL,
    @TestMode     bit = 0,
    @Problem      nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @one dbo.IdList;
    INSERT @one (Id) VALUES (@PersonnelNo);
    EXEC sel.usp_Idp_ApproveMany @LoginName = @LoginName, @CycleStageId = @CycleStageId,
         @People = @one, @AsOf = @AsOf, @TestMode = @TestMode, @Problem = @Problem OUTPUT;
END
GO
PRINT '  sel.usp_Idp_Approve               applied';
GO

/* sel.usp_Idp_Risk — demand against supply per organisation: days owed against
   successors available, banded.                                                       */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Risk
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope
    SELECT cc.PersonnelNo FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @cycleId;

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    /* What is already assigned, per person and requirement.  It is aggregated here
       rather than inside the sum below: SQL Server will not aggregate an expression that
       contains a subquery, and folding it in first is also one pass instead of one per
       row. */
    ;WITH assigned AS
    (
        SELECT cv.PersonnelNo, cv.DevEventId, DaysAssigned = SUM(cv.Days)
        FROM sel.IdpCoverage cv
        WHERE cv.CycleId = @cycleId
        GROUP BY cv.PersonnelNo, cv.DevEventId
    ),
    shortfall AS
    (
        SELECT e.OrgCode, o.PersonnelNo, IsSummed = k.EvalModeCode,
               /* Days owed: this requirement's floor, less what is already assigned,
                  and never less than nothing. */
               DaysOwed = CASE WHEN k.EvalModeCode = N'SUM'
                               THEN CASE WHEN ISNULL(ev.SumFloor, 0) - ISNULL(a.DaysAssigned, 0) > 0
                                         THEN ISNULL(ev.SumFloor, 0) - ISNULL(a.DaysAssigned, 0)
                                         ELSE 0 END
                               ELSE 0 END
        FROM #obl o
        JOIN sel.DevEvent ev ON ev.DevEventId = o.DevEventId
        JOIN sel.RequirementKind k ON k.KindCode = ev.KindCode
        JOIN sel.Employee e ON e.PersonnelNo = o.PersonnelNo
        LEFT JOIN assigned a ON a.PersonnelNo = o.PersonnelNo AND a.DevEventId = o.DevEventId
        WHERE o.IsMet = 0
    ),
    owed AS
    (
        SELECT OrgCode,
               DaysOwed = SUM(DaysOwed),
               PeopleOwing = COUNT(DISTINCT CASE WHEN IsSummed = N'SUM' THEN PersonnelNo END)
        FROM shortfall
        GROUP BY OrgCode
    )
    SELECT w.OrgCode, o.Name AS OrgName,
           DaysOwed = CAST(w.DaysOwed AS int),
           w.PeopleOwing,
           SuccessorsAvailable = (SELECT COUNT(*) FROM sel.CycleCandidate cc
                                  JOIN sel.Employee e2 ON e2.PersonnelNo = cc.PersonnelNo
                                  WHERE cc.CycleId = @cycleId AND e2.OrgCode = w.OrgCode),
           /* Banded: Nothing outstanding / 1-120 / 121-360 / over 360. */
           Band = CASE WHEN w.DaysOwed <= 0  THEN N'Nothing outstanding'
                       WHEN w.DaysOwed <= 120 THEN N'1–120 days'
                       WHEN w.DaysOwed <= 360 THEN N'121–360 days'
                       ELSE N'Over 360 days' END,
           BandRole = CASE WHEN w.DaysOwed <= 0  THEN N'positive'
                           WHEN w.DaysOwed <= 120 THEN N'neutral'
                           WHEN w.DaysOwed <= 360 THEN N'warning'
                           ELSE N'danger' END
    FROM owed w
    LEFT JOIN sel.OrgNode o ON o.OrgCode = w.OrgCode
    ORDER BY w.DaysOwed DESC;

    DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_Risk                  applied';
GO

/* sel.usp_Idp_Export — the cohort's plans as one flat result set for CSV and XLSX.
   It streams from the same procedure the screen reads, with paging off, so an export
   can never disagree with what was on screen.                                         */
CREATE OR ALTER PROCEDURE sel.usp_Idp_Export
    @LoginName    nvarchar(128),
    @CycleStageId int,
    @AsOf         date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cycleId int = (SELECT p.CycleId FROM sel.CycleStage s
                            JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                            WHERE s.CycleStageId = @CycleStageId);

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope
    SELECT cc.PersonnelNo FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @cycleId;

    CREATE TABLE #obl
    (
        PersonnelNo nvarchar(30) NOT NULL, DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        EventCode nvarchar(60) NULL, EventName nvarchar(300) NULL, KindCode nvarchar(30) NULL,
        IsMust int NOT NULL, IsMet int NOT NULL, Why nvarchar(600) NULL,
        Sources nvarchar(400) NULL, LevelNo int NULL
    );
    EXEC sel.usp_Idp_OpenRequirements_Into @CycleId = @cycleId, @AsOf = @AsOf;

    SELECT [Personnel No] = ob.PersonnelNo,
           [Name] = e.FullName,
           [Organisation] = o.Name,
           [Job title] = e.JobTitle,
           [Requirement] = ob.EventName,
           [Item code] = ob.ItemCode,
           [Source] = ob.Sources,
           [Must] = CASE WHEN ob.IsMust = 1 THEN N'Yes' ELSE N'No' END,
           [Met] = CASE WHEN ob.IsMet = 1 THEN N'Yes' ELSE N'No' END,
           [Why] = ob.Why,
           [Status] = ISNULL(sv.Name, N'Open'),
           [Session] = ds.SessionCode,
           [Session starts] = ds.StartDate,
           [Pencilled date] = i.PencilledDate,
           [Coverage days] = (SELECT SUM(cv.Days) FROM sel.IdpCoverage cv
                              WHERE cv.CycleId = @cycleId AND cv.PersonnelNo = ob.PersonnelNo
                                AND cv.DevEventId = ob.DevEventId),
           [Target date] = sel.fn_IdpTargetDate(@cycleId, ob.PersonnelNo, @CycleStageId),
           [Approved on] = (SELECT ApprovedOnUtc FROM sel.IdpApproval a
                            WHERE a.CycleId = @cycleId AND a.PersonnelNo = ob.PersonnelNo),
           [Approved by] = (SELECT ApprovedByLogin FROM sel.IdpApproval a
                            WHERE a.CycleId = @cycleId AND a.PersonnelNo = ob.PersonnelNo)
    FROM #obl ob
    JOIN sel.Employee e ON e.PersonnelNo = ob.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    LEFT JOIN sel.IdpItem i ON i.CycleId = @cycleId AND i.PersonnelNo = ob.PersonnelNo AND i.DevEventId = ob.DevEventId
    LEFT JOIN cfg.DomainValue sv ON sv.DomainValueId = i.StatusValueId
    LEFT JOIN sel.DevSession ds ON ds.DevSessionId = i.DevSessionId
    ORDER BY e.FullName, ob.EventCode;

    DROP TABLE #obl; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Idp_Export                applied';
GO

/* The coverage balance metric this file writes needs a definition like any other. */
MERGE sel.MetricDefinition AS t
USING (VALUES (N'CoverageDaysPlanned', N'Coverage days planned',
               N'Days of coverage assigned in a development plan, deducted as they are assigned.', N'number', 60))
    AS s (MetricKey, Name, Description, DataType, SortOrder)
   ON t.MetricKey = s.MetricKey
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MetricKey, Name, Description, DataType, SortOrder)
    VALUES (s.MetricKey, s.Name, s.Description, s.DataType, s.SortOrder);
PRINT '  sel.MetricDefinition              extended';
GO

PRINT '== 12_idp complete ===================================================';
GO
