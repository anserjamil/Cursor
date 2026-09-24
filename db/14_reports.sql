/* =====================================================================================
   14_reports.sql  —  read models, not new logic
   -------------------------------------------------------------------------------------
   A report that disagrees with a stage screen is a bug in the report, so each of these
   reads the same functions and procedures the screens read: sel.fn_CandidateBox for the
   funnel, sel.usp_Readiness_Spread for the distribution, sec.fn_UserOrgScope for who is
   counted at all.

   Every report returns three result sets, in this order:
     1. its columns  (key, caption, data type, alignment)
     2. its rows
     3. its note     (one sentence saying what the figures mean, and any caveat)
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 14_reports ========================================================';
GO

/* The report registry, so the Reports screen is data rather than a switch. */
IF OBJECT_ID('sel.ReportDefinition') IS NULL
BEGIN
    CREATE TABLE sel.ReportDefinition
    (
        ReportDefinitionId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_ReportDefinition PRIMARY KEY,
        ReportKey    nvarchar(60)  NOT NULL CONSTRAINT UQ_sel_ReportDefinition_Key UNIQUE,
        Name         nvarchar(160) NOT NULL,
        Description  nvarchar(600) NULL,
        ProcedureName nvarchar(160) NOT NULL,
        NeedsCycle   bit           NOT NULL CONSTRAINT DF_sel_ReportDefinition_Cycle DEFAULT (1),
        SortOrder    int           NOT NULL CONSTRAINT DF_sel_ReportDefinition_Sort  DEFAULT (0),
        IsActive     bit           NOT NULL CONSTRAINT DF_sel_ReportDefinition_Act   DEFAULT (1)
    );
    PRINT '  sel.ReportDefinition              created';
END
ELSE PRINT '  sel.ReportDefinition              skipped';
GO

/* sel.usp_Report_Pipeline — the funnel counts, and each as a share of those identified.
   It reads sel.fn_CandidateBox, so it cannot disagree with the stage screen.           */
CREATE OR ALTER PROCEDURE sel.usp_Report_Pipeline
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT ColumnKey, Caption, DataType, Align, SortOrder FROM (VALUES
        (N'ProcessName', N'Process',   N'text',   N'left',  10),
        (N'StageName',   N'Stage',     N'text',   N'left',  20),
        (N'Caption',     N'Box',       N'text',   N'left',  30),
        (N'Cnt',         N'People',    N'number', N'right', 40),
        (N'SharePct',    N'Share',     N'share',  N'right', 50)
    ) v (ColumnKey, Caption, DataType, Align, SortOrder) ORDER BY SortOrder;

    /* Everyone in the pool, once, inside this viewer's organisations. */
    CREATE TABLE #cand (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY, SourceCode nvarchar(30) NOT NULL);
    INSERT #cand
    SELECT cc.PersonnelNo, cc.SourceCode
    FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    WHERE cc.CycleId = @CycleId;

    DECLARE @identified int = (SELECT COUNT(*) FROM #cand);

    SELECT p.Name AS ProcessName, s.Name AS StageName, fp.Caption, fp.GroupNo, fp.SortOrder,
           fp.SemanticRole, fp.IsOutcome,
           Cnt = CASE WHEN fp.IsOutcome = 1
                      THEN (SELECT COUNT(*) FROM #cand c
                            WHERE sel.fn_CandidateBox(s.StageKindCode,
                                    (SELECT TOP (1) dv.ValueCode FROM sel.CandidateDecision d
                                     JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
                                     WHERE d.CycleStageId = s.CycleStageId AND d.PersonnelNo = c.PersonnelNo
                                     ORDER BY d.DecisionId DESC), c.SourceCode)
                                  IN (SELECT PillCode FROM sel.FunnelPill
                                      WHERE StageKindCode = s.StageKindCode AND CountsToTotal = 1))
                      ELSE (SELECT COUNT(*) FROM #cand c
                            WHERE sel.fn_CandidateBox(s.StageKindCode,
                                    (SELECT TOP (1) dv.ValueCode FROM sel.CandidateDecision d
                                     JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
                                     WHERE d.CycleStageId = s.CycleStageId AND d.PersonnelNo = c.PersonnelNo
                                     ORDER BY d.DecisionId DESC), c.SourceCode) = fp.PillCode) END,
           /* The share is returned as a count and a total: the formatter decides how it
              reads, so a non-zero count never prints as 0%. */
           ShareOf = @identified
    FROM sel.CycleProcess p
    JOIN sel.CycleStage s ON s.CycleProcessId = p.CycleProcessId
    JOIN sel.FunnelPill fp ON fp.StageKindCode = s.StageKindCode
    WHERE p.CycleId = @CycleId
    ORDER BY p.SortOrder, s.SortOrder, fp.GroupNo, fp.SortOrder;

    SELECT Note = N'Counted against the ' + CONVERT(nvarchar(20), @identified)
                + N' people in this cycle''s pool that you are granted. '
                + N'The boxes are the same ones the stage screens show, read from the same rule.';

    DROP TABLE #cand;
END
GO
PRINT '  sel.usp_Report_Pipeline           applied';
GO

/* sel.usp_Report_DecisionsByLevel — who decided what, at which management level. */
CREATE OR ALTER PROCEDURE sel.usp_Report_DecisionsByLevel
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ColumnKey, Caption, DataType, Align, SortOrder FROM (VALUES
        (N'LevelName',    N'Decided by',  N'text',   N'left',  10),
        (N'DecisionName', N'Decision',    N'text',   N'left',  20),
        (N'Cnt',          N'Decisions',   N'number', N'right', 30),
        (N'People',       N'People',      N'number', N'right', 40),
        (N'TestCount',    N'Of which test', N'number', N'right', 50)
    ) v (ColumnKey, Caption, DataType, Align, SortOrder) ORDER BY SortOrder;

    SELECT LevelName = ISNULL(pv.Name, N'(not recorded)'),
           DecisionName = dv.Name, DecisionRole = dv.SemanticRole,
           Cnt = COUNT(*),
           People = COUNT(DISTINCT d.PersonnelNo),
           TestCount = SUM(CAST(d.IsTest AS int)),
           ShareOf = (SELECT COUNT(*) FROM sel.CandidateDecision d2
                      JOIN sec.fn_UserOrgScope(@LoginName) s2 ON s2.OrgCode = d2.OrgCode
                      WHERE d2.CycleId = @CycleId)
    FROM sel.CandidateDecision d
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = d.OrgCode
    JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
    LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = d.PerformerLevelValueId
    WHERE d.CycleId = @CycleId
    GROUP BY pv.Name, pv.SortOrder, dv.Name, dv.SemanticRole, dv.SortOrder
    ORDER BY ISNULL(pv.SortOrder, 999), dv.SortOrder;

    SELECT Note = N'Every decision row, including the ones that cleared an earlier decision, '
                + N'because clearing is itself a decision. Decisions taken in test mode are counted separately.';
END
GO
PRINT '  sel.usp_Report_DecisionsByLevel   applied';
GO

/* sel.usp_Report_NominationsByOrg — where the nominations came from. */
CREATE OR ALTER PROCEDURE sel.usp_Report_NominationsByOrg
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ColumnKey, Caption, DataType, Align, SortOrder FROM (VALUES
        (N'OrgName',    N'Organisation', N'text',   N'left',  10),
        (N'InPool',     N'In the pool',  N'number', N'right', 20),
        (N'Nominated',  N'Nominated',    N'number', N'right', 30),
        (N'Watched',    N'Watch list',   N'number', N'right', 40),
        (N'Dropped',    N'Dropped',      N'number', N'right', 50),
        (N'SharePct',   N'Nominated share', N'share', N'right', 60)
    ) v (ColumnKey, Caption, DataType, Align, SortOrder) ORDER BY SortOrder;

    SELECT o.Name AS OrgName, cc.OrgCode,
           InPool = COUNT(DISTINCT cc.PersonnelNo),
           Nominated = COUNT(DISTINCT CASE WHEN latest.ValueCode IN (N'NOMINATED', N'KEPT') THEN cc.PersonnelNo END),
           Watched   = COUNT(DISTINCT CASE WHEN latest.ValueCode = N'WATCH'   THEN cc.PersonnelNo END),
           Dropped   = COUNT(DISTINCT CASE WHEN latest.ValueCode = N'DROPPED' THEN cc.PersonnelNo END),
           /* The share's numerator and denominator, for the one formatter. */
           ShareCount = COUNT(DISTINCT CASE WHEN latest.ValueCode IN (N'NOMINATED', N'KEPT') THEN cc.PersonnelNo END),
           ShareOf = COUNT(DISTINCT cc.PersonnelNo)
    FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    LEFT JOIN sel.OrgNode o ON o.OrgCode = cc.OrgCode
    OUTER APPLY (SELECT TOP (1) dv.ValueCode
                 FROM sel.CandidateDecision d
                 JOIN cfg.DomainValue dv ON dv.DomainValueId = d.DecisionValueId
                 WHERE d.CycleId = cc.CycleId AND d.PersonnelNo = cc.PersonnelNo
                   AND dv.ValueCode <> N'NONE'
                 ORDER BY d.DecisionId DESC) latest
    WHERE cc.CycleId = @CycleId
    GROUP BY o.Name, cc.OrgCode
    ORDER BY COUNT(DISTINCT cc.PersonnelNo) DESC, o.Name;

    SELECT Note = N'One row per organisation, counting each person once at their latest decision. '
                + N'Only organisations you have been granted appear, so two viewers will see different totals.';
END
GO
PRINT '  sel.usp_Report_NominationsByOrg   applied';
GO

/* sel.usp_Report_ReadinessDistribution — the same figures the design step shows, because
   it calls the same procedure.                                                         */
CREATE OR ALTER PROCEDURE sel.usp_Report_ReadinessDistribution
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ColumnKey, Caption, DataType, Align, SortOrder FROM (VALUES
        (N'LevelCode',    N'Level',          N'code',   N'left',  10),
        (N'Name',         N'Name',           N'text',   N'left',  20),
        (N'ThresholdPct', N'Threshold',      N'number', N'right', 30),
        (N'ClearCut',     N'Clear this cut', N'number', N'right', 40),
        (N'AtThisLevel',  N'Held here',      N'number', N'right', 50)
    ) v (ColumnKey, Caption, DataType, Align, SortOrder) ORDER BY SortOrder;

    /* The report is a read model: it calls the engine, it does not re-implement it. */
    EXEC sel.usp_Readiness_Spread @LoginName = @LoginName, @CycleId = @CycleId, @AsOf = @AsOf;
END
GO
PRINT '  sel.usp_Report_ReadinessDistribution applied';
GO

/* sel.usp_Report_AssessmentCoverage — who has been assessed, and who has not. */
CREATE OR ALTER PROCEDURE sel.usp_Report_AssessmentCoverage
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT ColumnKey, Caption, DataType, Align, SortOrder FROM (VALUES
        (N'ItemCode',  N'Assessment', N'code',   N'left',  10),
        (N'ItemName',  N'Name',       N'text',   N'left',  20),
        (N'Taken',     N'Taken',      N'number', N'right', 30),
        (N'Passed',    N'Passed',     N'number', N'right', 40),
        (N'Expired',   N'Expired',    N'number', N'right', 50),
        (N'SharePct',  N'Of the pool',N'share',  N'right', 60)
    ) v (ColumnKey, Caption, DataType, Align, SortOrder) ORDER BY SortOrder;

    DECLARE @pool int = (SELECT COUNT(*) FROM sel.CycleCandidate cc
                         JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
                         WHERE cc.CycleId = @CycleId);

    SELECT r.ItemCode, ItemName = ISNULL(ci.Name, r.ItemCode),
           Taken = COUNT(DISTINCT r.PersonnelNo),
           Passed = COUNT(DISTINCT CASE WHEN r.Status = N'Completed' THEN r.PersonnelNo END),
           /* An expired record is not a completion, and the report has to say so. */
           Expired = COUNT(DISTINCT CASE WHEN r.ExpiresOn IS NOT NULL AND r.ExpiresOn < @AsOf
                                         THEN r.PersonnelNo END),
           ShareCount = COUNT(DISTINCT r.PersonnelNo),
           ShareOf = @pool
    FROM sel.EmployeeRecord r
    JOIN sel.CycleCandidate cc ON cc.CycleId = @CycleId AND cc.PersonnelNo = r.PersonnelNo
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    LEFT JOIN sel.CatalogItem ci ON ci.KindCode = r.KindCode AND ci.ItemCode = r.ItemCode
    WHERE r.KindCode IN (N'ASSESSMENT', N'FEEDBACK360')
    GROUP BY r.ItemCode, ci.Name
    ORDER BY COUNT(DISTINCT r.PersonnelNo) DESC, r.ItemCode;

    SELECT Note = N'Counted against the ' + CONVERT(nvarchar(20), @pool)
                + N' people in this cycle''s pool that you are granted. '
                + N'An expired result is still counted as taken, and called out separately.';
END
GO
PRINT '  sel.usp_Report_AssessmentCoverage applied';
GO

/* sel.usp_Report_PopulationProfile — grade band, age band and gender across the pool.
   Gender and dates of birth are sensitive: they are reported in aggregate here, and
   still refused as filters everywhere else.                                            */
CREATE OR ALTER PROCEDURE sel.usp_Report_PopulationProfile
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    SELECT ColumnKey, Caption, DataType, Align, SortOrder FROM (VALUES
        (N'Dimension', N'Dimension', N'text',   N'left',  10),
        (N'Band',      N'Band',      N'text',   N'left',  20),
        (N'Cnt',       N'People',    N'number', N'right', 30),
        (N'SharePct',  N'Share',     N'share',  N'right', 40)
    ) v (ColumnKey, Caption, DataType, Align, SortOrder) ORDER BY SortOrder;

    CREATE TABLE #pool
    (
        PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY,
        GradeCode nvarchar(20) NULL, Gender nvarchar(20) NULL, BirthDate date NULL
    );
    INSERT #pool
    SELECT cc.PersonnelNo, e.GradeCode, e.Gender, e.BirthDate
    FROM sel.CycleCandidate cc
    JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = cc.OrgCode
    JOIN sel.Employee e ON e.PersonnelNo = cc.PersonnelNo
    WHERE cc.CycleId = @CycleId;

    DECLARE @total int = (SELECT COUNT(*) FROM #pool);

    SELECT Dimension = N'Grade', Band = ISNULL(GradeCode, N'(not recorded)'),
           Cnt = COUNT(*), ShareCount = COUNT(*), ShareOf = @total, SortOrder = 1
    FROM #pool GROUP BY GradeCode
    UNION ALL
    SELECT N'Age band',
           CASE WHEN BirthDate IS NULL THEN N'(not recorded)'
                WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 30 THEN N'Under 30'
                WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 40 THEN N'30–39'
                WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 50 THEN N'40–49'
                WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 60 THEN N'50–59'
                ELSE N'60 and over' END,
           COUNT(*), COUNT(*), @total, 2
    FROM #pool
    GROUP BY CASE WHEN BirthDate IS NULL THEN N'(not recorded)'
                  WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 30 THEN N'Under 30'
                  WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 40 THEN N'30–39'
                  WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 50 THEN N'40–49'
                  WHEN DATEDIFF(YEAR, BirthDate, @AsOf) < 60 THEN N'50–59'
                  ELSE N'60 and over' END
    UNION ALL
    SELECT N'Gender', ISNULL(Gender, N'(not recorded)'), COUNT(*), COUNT(*), @total, 3
    FROM #pool GROUP BY Gender
    ORDER BY SortOrder, Cnt DESC;

    SELECT Note = N'The ' + CONVERT(nvarchar(20), @total) + N' people in this cycle''s pool that you are granted. '
                + N'Gender and date of birth are reported here in aggregate only; they stay readable on a '
                + N'person''s record and refused as filters.';

    DROP TABLE #pool;
END
GO
PRINT '  sel.usp_Report_PopulationProfile  applied';
GO

/* sel.usp_Report_List — the report menu, as data. */
CREATE OR ALTER PROCEDURE sel.usp_Report_List
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ReportDefinitionId, ReportKey, Name, Description, ProcedureName, NeedsCycle, SortOrder
    FROM sel.ReportDefinition WHERE IsActive = 1 ORDER BY SortOrder, Name;
END
GO
PRINT '  sel.usp_Report_List               applied';
GO

/* sel.usp_Report_Run — one door for every report, so the controller holds no switch. */
CREATE OR ALTER PROCEDURE sel.usp_Report_Run
    @LoginName nvarchar(128),
    @ReportKey nvarchar(60),
    @CycleId   int = NULL,
    @AsOf      date = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @Problem = NULL;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @proc nvarchar(160), @needsCycle bit, @name nvarchar(160);
    SELECT @proc = ProcedureName, @needsCycle = NeedsCycle, @name = Name
    FROM sel.ReportDefinition WHERE ReportKey = @ReportKey AND IsActive = 1;

    IF @proc IS NULL
    BEGIN
        SET @Problem = N'There is no report called ' + ISNULL(@ReportKey, N'(none)') + N'.';
        SELECT TOP (0) CAST(NULL AS nvarchar(60)) AS ColumnKey;
        SELECT TOP (0) CAST(NULL AS nvarchar(200)) AS Band;
        SELECT Note = @Problem;
        RETURN;
    END;

    IF @needsCycle = 1 AND @CycleId IS NULL
    BEGIN
        SET @Problem = N'"' + @name + N'" is about one cycle, so pick a cycle first.';
        SELECT TOP (0) CAST(NULL AS nvarchar(60)) AS ColumnKey;
        SELECT TOP (0) CAST(NULL AS nvarchar(200)) AS Band;
        SELECT Note = @Problem;
        RETURN;
    END;

    IF @CycleId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId)
    BEGIN
        SET @Problem = N'That cycle no longer exists.';
        SELECT TOP (0) CAST(NULL AS nvarchar(60)) AS ColumnKey;
        SELECT TOP (0) CAST(NULL AS nvarchar(200)) AS Band;
        SELECT Note = @Problem;
        RETURN;
    END;

    DECLARE @sql nvarchar(max) = N'EXEC ' + @proc + N' @LoginName = @LoginName, @CycleId = @CycleId, @AsOf = @AsOf;';
    BEGIN TRY
        EXEC sp_executesql @sql,
             N'@LoginName nvarchar(128), @CycleId int, @AsOf date',
             @LoginName = @LoginName, @CycleId = @CycleId, @AsOf = @AsOf;
    END TRY
    BEGIN CATCH
        SET @Problem = N'"' + @name + N'" could not be produced: ' + ERROR_MESSAGE();
        SELECT TOP (0) CAST(NULL AS nvarchar(60)) AS ColumnKey;
        SELECT TOP (0) CAST(NULL AS nvarchar(200)) AS Band;
        SELECT Note = @Problem;
    END CATCH;
END
GO
PRINT '  sel.usp_Report_Run                applied';
GO

MERGE sel.ReportDefinition AS t
USING (VALUES
    (N'PIPELINE',     N'Cycle pipeline',
     N'The funnel counts at each stage, and each as a share of those identified.',
     N'sel.usp_Report_Pipeline', 1, 10),
    (N'DECISIONS',    N'Decisions by level',
     N'Which management level took which decisions, and how many were taken in test mode.',
     N'sel.usp_Report_DecisionsByLevel', 1, 20),
    (N'NOMINATIONS',  N'Nominations by organisation',
     N'Where the nominations came from, one row per organisation.',
     N'sel.usp_Report_NominationsByOrg', 1, 30),
    (N'READINESS',    N'Readiness distribution',
     N'How many clear each level''s cut, and how many are held at each level.',
     N'sel.usp_Report_ReadinessDistribution', 1, 40),
    (N'ASSESSMENT',   N'Assessment coverage',
     N'Who has taken each assessment, who passed, and whose result has expired.',
     N'sel.usp_Report_AssessmentCoverage', 1, 50),
    (N'POPULATION',   N'Population profile',
     N'The pool by grade band, age band and gender.',
     N'sel.usp_Report_PopulationProfile', 1, 60)
) AS s (ReportKey, Name, Description, ProcedureName, NeedsCycle, SortOrder)
   ON t.ReportKey = s.ReportKey
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             ProcedureName = s.ProcedureName, NeedsCycle = s.NeedsCycle, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ReportKey, Name, Description, ProcedureName, NeedsCycle, SortOrder)
    VALUES (s.ReportKey, s.Name, s.Description, s.ProcedureName, s.NeedsCycle, s.SortOrder);
PRINT '  sel.ReportDefinition              seeded';
GO

PRINT '== 14_reports complete ===============================================';
GO
