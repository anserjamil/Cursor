/* =====================================================================================
   08_pool_and_open.sql  —  resolving the pool, validating the design, opening the cycle
   -------------------------------------------------------------------------------------
   The criteria builder writes sets of conditions; sel.usp_Criteria_BuildWhere turns them
   into one predicate over the mapped roster table; sel.usp_Pool_Preview answers "how many
   people is that" with a reach count per set, a sample, and — when the question could not
   be asked at all — a sentence instead of a zero.

   Each person has exactly one roster row, so the prototype's set operations over people
   (or also / and also / but not) reduce exactly to OR / AND / AND NOT over that row.
   That equivalence is what keeps a 79,000-row preview to a single scan.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 08_pool_and_open ==================================================';
GO

/* sel.vw_Candidate — the stable core of a candidate, for every screen that does not need
   the wide roster.  The ~200-column record is reached through the mapping, not mirrored
   here, so a new roster column never needs a migration.                                 */
CREATE OR ALTER VIEW sel.vw_Candidate
AS
SELECT e.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, o.OrgLevel,
       e.JobTitle, e.PermJobSuffix, e.PermJobSuffixDesc, e.CurrentJobSuffix,
       e.GradeCode, e.ManagementLevelCode, e.IsActive, e.PermChiefInd,
       e.HireDate, e.PromotionDate, e.BirthDate, e.Gender, e.Nationality, e.Email
FROM sel.Employee e
LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode;
GO
PRINT '  sel.vw_Candidate                  applied';
GO

/* sel.usp_RosterField_Sync — discovers every roster column, switched off.  Approving one
   makes it available to the criteria builder; the sensitive toggle is a separate
   question and is never set by discovery.                                               */
CREATE OR ALTER PROCEDURE sel.usp_RosterField_Sync
    @LoginName nvarchar(128),
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/Setup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS RosterFieldId;
        RETURN;
    END;

    DECLARE @schema nvarchar(128), @table nvarchar(128), @isMapped bit;
    SELECT @schema = SchemaName, @table = TableName, @isMapped = IsMapped
    FROM sel.TableMapping WHERE SourceKey = N'ROSTER';

    IF ISNULL(@isMapped, 0) = 0
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS int) AS RosterFieldId;
        RETURN;
    END;

    BEGIN TRAN;

    /* Anything previously discovered that is no longer in the table is marked absent
       rather than deleted, so a criterion that names it can still explain itself. */
    UPDATE sel.RosterField SET IsPresent = 0
    WHERE SourceKind = N'ROSTER'
      AND FieldName NOT IN (SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
                            WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @table);

    MERGE sel.RosterField AS t
    USING (SELECT ColumnName = c.COLUMN_NAME,
                  SqlType    = c.DATA_TYPE,
                  DataType   = sel.fn_SqlTypeToDataType(c.DATA_TYPE),
                  OrdinalPos = c.ORDINAL_POSITION
           FROM INFORMATION_SCHEMA.COLUMNS c
           WHERE c.TABLE_SCHEMA = @schema AND c.TABLE_NAME = @table) AS s
       ON t.FieldName = s.ColumnName AND t.SourceKind = N'ROSTER'
    WHEN MATCHED THEN
        UPDATE SET SqlType = s.SqlType, DataType = s.DataType,
                   SortOrder = s.OrdinalPos, IsPresent = 1, LastSeenOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        /* Discovered switched off. */
        INSERT (FieldName, Caption, DataType, SqlType, SourceKind, IsEnabled, IsSensitive,
                GroupName, SortOrder, LastSeenOnUtc)
        VALUES (s.ColumnName, s.ColumnName, s.DataType, s.SqlType, N'ROSTER', 0, 0,
                N'Roster', s.OrdinalPos, SYSUTCDATETIME());

    /* Derived figures are filterable too, and are read from sel.EmployeeMetric. */
    MERGE sel.RosterField AS t
    USING (SELECT MetricKey, Name, DataType FROM sel.MetricDefinition WHERE IsActive = 1) AS s
       ON t.FieldName = s.MetricKey AND t.SourceKind = N'METRIC'
    WHEN MATCHED THEN
        UPDATE SET Caption = s.Name, DataType = s.DataType, IsPresent = 1, LastSeenOnUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (FieldName, Caption, DataType, SqlType, SourceKind, IsEnabled, IsSensitive,
                GroupName, SortOrder, LastSeenOnUtc)
        VALUES (s.MetricKey, s.Name, s.DataType, NULL, N'METRIC', 0, 0, N'Derived', 9000, SYSUTCDATETIME());

    /* Usage count: how many live criteria name each field. */
    UPDATE f SET UsageCount = ISNULL(x.N, 0)
    FROM sel.RosterField f
    OUTER APPLY (SELECT N = COUNT(*) FROM sel.CycleCriterion c WHERE c.RosterFieldId = f.RosterFieldId) x;

    COMMIT;

    EXEC audit.usp_Log @TableName = N'sel.RosterField', @KeyText = N'(sync)',
                       @ActionCode = N'SYNC', @LoginName = @LoginName;
    EXEC sel.usp_RosterField_List @LoginName = @LoginName;
END
GO
PRINT '  sel.usp_RosterField_Sync          applied';
GO

/* =====================================================================================
   sel.usp_Criteria_BuildWhere — the criteria as one predicate over the roster row
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Criteria_BuildWhere
    @CycleId int,
    @Alias   nvarchar(20) = N'rs',
    @AsOf    date = NULL,
    @Where   nvarchar(max) OUTPUT,
    @Problem nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    SET @Where = NULL; SET @Problem = NULL;

    IF NOT EXISTS (SELECT 1 FROM sel.CycleCriterionSet WHERE CycleId = @CycleId)
    BEGIN
        /* No criteria is not an error: the whole active roster is the pool. */
        SET @Where = N'(1 = 1)';
        RETURN;
    END;

    /* A criterion whose field is disabled, sensitive or absent cannot be asked.  Refuse
       with a sentence rather than quietly dropping the condition, which would widen the
       pool without anybody noticing. */
    DECLARE @badField nvarchar(300);
    SELECT TOP (1) @badField = f.FieldName +
           CASE WHEN f.IsPresent = 0  THEN N' is no longer in the roster'
                WHEN f.IsSensitive = 1 THEN N' is a sensitive field and cannot be filtered on'
                WHEN f.IsEnabled = 0   THEN N' has not been approved for use in criteria'
                ELSE N'' END
    FROM sel.CycleCriterion c
    JOIN sel.CycleCriterionSet cs ON cs.CriterionSetId = c.CriterionSetId
    JOIN sel.RosterField f ON f.RosterFieldId = c.RosterFieldId
    WHERE cs.CycleId = @CycleId
      AND (f.IsPresent = 0 OR f.IsSensitive = 1 OR f.IsEnabled = 0);

    IF @badField IS NOT NULL
    BEGIN
        SET @Problem = N'This pool cannot be resolved: ' + @badField + N'.';
        RETURN;
    END;

    DECLARE @folded nvarchar(max) = NULL, @first bit = 1;
    DECLARE @setId int, @mode nvarchar(60), @join nvarchar(60);

    DECLARE setCur CURSOR LOCAL FAST_FORWARD FOR
        SELECT cs.CriterionSetId, mv.ValueCode, jv.ValueCode
        FROM sel.CycleCriterionSet cs
        JOIN cfg.DomainValue mv ON mv.DomainValueId = cs.SetModeValueId
        LEFT JOIN cfg.DomainValue jv ON jv.DomainValueId = cs.SetJoinValueId
        WHERE cs.CycleId = @CycleId
        ORDER BY cs.SortOrder, cs.SetLabel;

    OPEN setCur; FETCH NEXT FROM setCur INTO @setId, @mode, @join;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @parts nvarchar(max) =
            STUFF((SELECT CASE WHEN @mode = N'ALL' THEN N' AND ' ELSE N' OR ' END
                        + cfg.fn_BuildPredicate(
                              /* A roster column is read from the roster row; a derived
                                 figure is read from sel.EmployeeMetric for that person. */
                              CASE WHEN f.SourceKind = N'METRIC'
                                   THEN N'(SELECT TOP (1) em.NumValue FROM sel.EmployeeMetric em WHERE em.PersonnelNo = '
                                      + @Alias + N'.' + QUOTENAME((SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'ROSTER'))
                                      + N' AND em.MetricKey = ' + cfg.fn_EscapeLiteral(f.FieldName) + N')'
                                   ELSE @Alias + N'.' + QUOTENAME(f.FieldName) END,
                              c.OperatorCode, c.Value1, c.Value2, f.DataType, @AsOf)
                   FROM sel.CycleCriterion c
                   JOIN sel.RosterField f ON f.RosterFieldId = c.RosterFieldId
                   WHERE c.CriterionSetId = @setId
                   ORDER BY c.SortOrder, c.CriterionId
                   FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'),
                  1, CASE WHEN @mode = N'ALL' THEN 5 ELSE 4 END, N'');

        DECLARE @setSql nvarchar(max);
        IF @parts IS NULL                       SET @setSql = N'(1 = 1)';
        ELSE IF @mode = N'NONE'                 SET @setSql = N'(NOT (' + @parts + N'))';
        ELSE                                    SET @setSql = N'(' + @parts + N')';

        IF @first = 1 BEGIN SET @folded = @setSql; SET @first = 0; END
        ELSE
            /* or also = union, and also = intersection, but not = difference. */
            SET @folded = N'(' + @folded +
                CASE ISNULL(@join, N'INTERSECT')
                     WHEN N'UNION'     THEN N' OR '
                     WHEN N'EXCEPT'    THEN N' AND NOT '
                     ELSE N' AND ' END
                + @setSql + N')';

        FETCH NEXT FROM setCur INTO @setId, @mode, @join;
    END;

    CLOSE setCur; DEALLOCATE setCur;
    SET @Where = ISNULL(@folded, N'(1 = 1)');
END
GO
PRINT '  sel.usp_Criteria_BuildWhere       applied';
GO

/* =====================================================================================
   sel.usp_Pool_Preview — the reach, the sample and the drill-down
   -------------------------------------------------------------------------------------
   Result 1: the rule read back, with a reach count per set and in total.
   Result 2: the sample / drill-down page, inside the viewer's organisation scope.
   Result 3: the totals, and whether the figures were sampled.

   When the question cannot be asked at all, @Problem carries the sentence and the counts
   come back NULL.  Distinguish "nobody qualifies" from "the question could not be asked":
   the UI must never render the second as a zero.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Pool_Preview
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL,
    @PageNo    int = 1,
    @PageSize  int = NULL,
    @Search    nvarchar(200) = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageNo IS NULL OR @PageNo < 1 SET @PageNo = 1;
    SET @Problem = NULL;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'ROSTER');
    DECLARE @keyCol nvarchar(128) = (SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'ROSTER');

    IF @obj IS NULL OR @keyCol IS NULL
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS nvarchar(10)) AS SetLabel;
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        SELECT TotalRows = CAST(NULL AS int), PoolCount = CAST(NULL AS int),
               IsSampled = CAST(0 AS bit), Problem = @Problem;
        RETURN;
    END;

    DECLARE @where nvarchar(max), @p nvarchar(400);
    EXEC sel.usp_Criteria_BuildWhere @CycleId = @CycleId, @Alias = N'rs', @AsOf = @AsOf,
                                     @Where = @where OUTPUT, @Problem = @p OUTPUT;
    IF @p IS NOT NULL
    BEGIN
        SET @Problem = @p;
        SELECT TOP (0) CAST(NULL AS nvarchar(10)) AS SetLabel;
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        SELECT TotalRows = CAST(NULL AS int), PoolCount = CAST(NULL AS int),
               IsSampled = CAST(0 AS bit), Problem = @Problem;
        RETURN;
    END;

    /* The matching personnel numbers, once, inside the viewer's organisation scope. */
    CREATE TABLE #hit (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);

    DECLARE @sql nvarchar(max) = N'
        INSERT #hit (PersonnelNo)
        SELECT DISTINCT CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol) + N')
        FROM ' + @obj + N' rs
        JOIN sel.Employee e ON e.PersonnelNo = CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol) + N')
        JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
        WHERE ' + @where + N';';

    BEGIN TRY
        EXEC sp_executesql @sql, N'@LoginName nvarchar(128)', @LoginName = @LoginName;
    END TRY
    BEGIN CATCH
        /* The question could not be asked.  Say so; never answer zero. */
        SET @Problem = N'This pool could not be resolved: ' + ERROR_MESSAGE();
        SELECT TOP (0) CAST(NULL AS nvarchar(10)) AS SetLabel;
        SELECT TOP (0) CAST(NULL AS nvarchar(30)) AS PersonnelNo;
        SELECT TotalRows = CAST(NULL AS int), PoolCount = CAST(NULL AS int),
               IsSampled = CAST(0 AS bit), Problem = @Problem;
        RETURN;
    END CATCH;

    /* 1 — the rule read back as a sentence, with per-set reach. */
    CREATE TABLE #setReach (SetLabel nvarchar(10), Sentence nvarchar(max), Reach int, SortOrder int);

    DECLARE @setId int, @label nvarchar(10), @mode nvarchar(60), @join nvarchar(60), @sort int;
    DECLARE setCur CURSOR LOCAL FAST_FORWARD FOR
        SELECT cs.CriterionSetId, cs.SetLabel, mv.Name, jv.Name, cs.SortOrder
        FROM sel.CycleCriterionSet cs
        JOIN cfg.DomainValue mv ON mv.DomainValueId = cs.SetModeValueId
        LEFT JOIN cfg.DomainValue jv ON jv.DomainValueId = cs.SetJoinValueId
        WHERE cs.CycleId = @CycleId ORDER BY cs.SortOrder, cs.SetLabel;

    OPEN setCur; FETCH NEXT FROM setCur INTO @setId, @label, @mode, @join, @sort;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @sentence nvarchar(max) =
            ISNULL(@join + N' ', N'') + N'Set ' + @label + N': ' + @mode + N' of ' +
            ISNULL(STUFF((SELECT N'; ' + f.Caption + N' ' + o.Name
                           + CASE WHEN o.Arity = 0 THEN N''
                                  WHEN o.Arity = 1 THEN N' ' + ISNULL(c.Value1, N'(no value)')
                                  ELSE N' ' + ISNULL(c.Value1, N'(no value)') + N' and ' + ISNULL(c.Value2, N'(no value)') END
                   FROM sel.CycleCriterion c
                   JOIN sel.RosterField f ON f.RosterFieldId = c.RosterFieldId
                   JOIN cfg.Operator o ON o.OperatorCode = c.OperatorCode
                   WHERE c.CriterionSetId = @setId ORDER BY c.SortOrder
                   FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N''), N'(no conditions yet)');

        /* This set's own reach, independent of the others. */
        DECLARE @setWhere nvarchar(max) =
            ISNULL(STUFF((SELECT N' AND ' + cfg.fn_BuildPredicate(
                                CASE WHEN f.SourceKind = N'METRIC'
                                     THEN N'(SELECT TOP (1) em.NumValue FROM sel.EmployeeMetric em WHERE em.PersonnelNo = rs.'
                                        + QUOTENAME(@keyCol) + N' AND em.MetricKey = ' + cfg.fn_EscapeLiteral(f.FieldName) + N')'
                                     ELSE N'rs.' + QUOTENAME(f.FieldName) END,
                                c.OperatorCode, c.Value1, c.Value2, f.DataType, @AsOf)
                          FROM sel.CycleCriterion c
                          JOIN sel.RosterField f ON f.RosterFieldId = c.RosterFieldId
                          WHERE c.CriterionSetId = @setId ORDER BY c.SortOrder
                          FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 5, N''), N'(1 = 1)');

        DECLARE @reach int = NULL;
        DECLARE @rsql nvarchar(max) = N'
            SELECT @reach = COUNT(DISTINCT CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol) + N'))
            FROM ' + @obj + N' rs
            JOIN sel.Employee e ON e.PersonnelNo = CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol) + N')
            JOIN sec.fn_UserOrgScope(@LoginName) sc ON sc.OrgCode = e.OrgCode
            WHERE ' + @setWhere + N';';
        BEGIN TRY
            EXEC sp_executesql @rsql, N'@LoginName nvarchar(128), @reach int OUTPUT',
                 @LoginName = @LoginName, @reach = @reach OUTPUT;
        END TRY
        BEGIN CATCH SET @reach = NULL; END CATCH;

        INSERT #setReach VALUES (@label, @sentence, @reach, @sort);
        FETCH NEXT FROM setCur INTO @setId, @label, @mode, @join, @sort;
    END;
    CLOSE setCur; DEALLOCATE setCur;

    SELECT SetLabel, Sentence, Reach, SortOrder FROM #setReach ORDER BY SortOrder;

    /* 2 — the sample / drill-down page. */
    /* The same columns sel.usp_Employee_Roster returns, in the same order: one record
       is filled from both. */
    SELECT c.PersonnelNo, c.FullName, c.OrgCode, c.OrgName, c.JobTitle,
           c.PermJobSuffix, c.PermJobSuffixDesc, c.GradeCode, c.ManagementLevelCode,
           c.HireDate, c.PromotionDate, c.IsActive, c.PermChiefInd
    FROM #hit h
    JOIN sel.vw_Candidate c ON c.PersonnelNo = h.PersonnelNo
    WHERE (@Search IS NULL OR c.FullName LIKE N'%' + @Search + N'%'
           OR c.PersonnelNo LIKE N'%' + @Search + N'%'
           OR c.JobTitle LIKE N'%' + @Search + N'%'
           OR c.OrgName LIKE N'%' + @Search + N'%')
    ORDER BY c.FullName
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    /* 3 — the totals. */
    SELECT TotalRows = (SELECT COUNT(*) FROM #hit h JOIN sel.vw_Candidate c ON c.PersonnelNo = h.PersonnelNo
                        WHERE (@Search IS NULL OR c.FullName LIKE N'%' + @Search + N'%'
                               OR c.PersonnelNo LIKE N'%' + @Search + N'%'
                               OR c.JobTitle LIKE N'%' + @Search + N'%'
                               OR c.OrgName LIKE N'%' + @Search + N'%')),
           PoolCount = (SELECT COUNT(*) FROM #hit),
           IsSampled = CAST(0 AS bit),
           Problem   = CAST(NULL AS nvarchar(400));

    DROP TABLE #setReach; DROP TABLE #hit;
END
GO
PRINT '  sel.usp_Pool_Preview              applied';
GO

/* =====================================================================================
   sel.usp_Cycle_Validate — what blocks opening, each with the step that fixes it
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_Validate
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL,
    /* The wizard wants all three result sets; sel.usp_Cycle_Open wants only the to-do
       list, because INSERT ... EXEC captures every set a procedure returns and would
       fail on the two that follow. One flag beats two procedures drifting apart. */
    @TodoOnly  bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @skipped TABLE (StepNo int PRIMARY KEY);
    INSERT @skipped SELECT StepNo FROM sel.CycleSkippedStep WHERE CycleId = @CycleId;

    DECLARE @fail TABLE (RuleCode nvarchar(60) PRIMARY KEY);

    /* Step 1 — the cycle itself. */
    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId AND (StartDate IS NULL OR EndDate IS NULL))
        INSERT @fail VALUES (N'CYCLE_NO_WINDOW');
    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId AND NULLIF(LTRIM(RTRIM(Name)), N'') IS NULL)
        INSERT @fail VALUES (N'CYCLE_NO_NAME');
    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId AND StartDate IS NOT NULL
                 AND EndDate IS NOT NULL AND EndDate < StartDate)
        INSERT @fail VALUES (N'CYCLE_WINDOW_BACKWARDS');
    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId AND NULLIF(LTRIM(RTRIM(OwnerLogin)), N'') IS NULL)
        INSERT @fail VALUES (N'CYCLE_NO_OWNER');

    /* Step 2 — the eligible pool. */
    IF NOT EXISTS (SELECT 1 FROM @skipped WHERE StepNo = 2)
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sel.CycleCriterionSet WHERE CycleId = @CycleId)
            INSERT @fail VALUES (N'POOL_NO_SET');

        /* An unfinished value: an operator that needs a value and has not got one. */
        IF EXISTS (SELECT 1 FROM sel.CycleCriterion c
                   JOIN sel.CycleCriterionSet cs ON cs.CriterionSetId = c.CriterionSetId
                   JOIN cfg.Operator o ON o.OperatorCode = c.OperatorCode
                   WHERE cs.CycleId = @CycleId
                     AND ((o.Arity >= 1 AND NULLIF(LTRIM(RTRIM(ISNULL(c.Value1, N''))), N'') IS NULL)
                       OR (o.Arity >= 2 AND NULLIF(LTRIM(RTRIM(ISNULL(c.Value2, N''))), N'') IS NULL)))
            INSERT @fail VALUES (N'POOL_UNFINISHED_VALUE');

        /* A pool linked but no membership table mapped. */
        IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId AND ExistingPoolCode IS NOT NULL)
           AND ISNULL((SELECT IsMapped FROM sel.TableMapping WHERE SourceKey = N'POOL'), 0) = 0
            INSERT @fail VALUES (N'POOL_LINK_UNMAPPED');
    END;

    /* Step 3 — frameworks. */
    IF NOT EXISTS (SELECT 1 FROM @skipped WHERE StepNo = 3)
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sel.CycleFramework WHERE CycleId = @CycleId)
            INSERT @fail VALUES (N'FRAMEWORK_NONE');
        IF EXISTS (SELECT 1 FROM sel.CycleFramework cf
                   JOIN sel.DevFramework f ON f.DevFrameworkId = cf.DevFrameworkId
                   JOIN cfg.DomainValue dv ON dv.DomainValueId = f.StatusValueId
                   WHERE cf.CycleId = @CycleId AND dv.ValueCode = N'DRAFT')
            INSERT @fail VALUES (N'FRAMEWORK_DRAFT');
        IF EXISTS (SELECT 1 FROM sel.CycleFramework cf
                   WHERE cf.CycleId = @CycleId
                     AND NOT EXISTS (SELECT 1 FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = cf.DevFrameworkId))
            INSERT @fail VALUES (N'FRAMEWORK_EMPTY');
        IF EXISTS (SELECT 1 FROM sel.CycleFramework cf
                   JOIN sel.DevFramework f ON f.DevFrameworkId = cf.DevFrameworkId
                   WHERE cf.CycleId = @CycleId AND f.IsActive = 0)
            INSERT @fail VALUES (N'FRAMEWORK_RETIRED');
    END;

    /* Step 4 — readiness levels. */
    IF NOT EXISTS (SELECT 1 FROM @skipped WHERE StepNo = 4)
    BEGIN
        IF EXISTS (SELECT 1 FROM sel.CycleReadiness WHERE CycleId = @CycleId
                     AND (NULLIF(LTRIM(RTRIM(LevelCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(Name)), N'') IS NULL))
            INSERT @fail VALUES (N'READINESS_NO_NAME');
        IF EXISTS (SELECT 1 FROM sel.CycleReadiness WHERE CycleId = @CycleId AND ThresholdPct IS NULL)
            INSERT @fail VALUES (N'READINESS_NO_PCT');
        IF EXISTS (SELECT ThresholdPct FROM sel.CycleReadiness WHERE CycleId = @CycleId
                   GROUP BY ThresholdPct HAVING COUNT(*) > 1)
            INSERT @fail VALUES (N'READINESS_DUP_PCT');
        IF EXISTS (SELECT 1 FROM sel.CycleReadiness WHERE CycleId = @CycleId)
           AND NOT EXISTS (SELECT 1 FROM sel.CycleFramework cf
                           JOIN sel.DevFrameworkItem i ON i.DevFrameworkId = cf.DevFrameworkId
                           WHERE cf.CycleId = @CycleId)
            INSERT @fail VALUES (N'READINESS_NO_EVENTS');
    END;

    /* Step 5 — stages. */
    IF NOT EXISTS (SELECT 1 FROM @skipped WHERE StepNo = 5)
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sel.CycleProcess WHERE CycleId = @CycleId)
            INSERT @fail VALUES (N'STAGE_NO_PROCESS');
        IF EXISTS (SELECT 1 FROM sel.CycleProcess p
                   WHERE p.CycleId = @CycleId
                     AND NOT EXISTS (SELECT 1 FROM sel.CycleStage s WHERE s.CycleProcessId = p.CycleProcessId))
            INSERT @fail VALUES (N'STAGE_NO_STAGES');
        IF EXISTS (SELECT 1 FROM sel.CycleStage s
                   JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                   WHERE p.CycleId = @CycleId AND (s.StartDate IS NULL OR s.EndDate IS NULL))
            INSERT @fail VALUES (N'STAGE_NO_WINDOW');
        IF EXISTS (SELECT 1 FROM sel.CycleStage s
                   JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                   JOIN sel.Cycle cy ON cy.CycleId = p.CycleId
                   WHERE p.CycleId = @CycleId AND s.StartDate IS NOT NULL AND cy.StartDate IS NOT NULL
                     AND (s.StartDate < cy.StartDate OR s.EndDate > cy.EndDate))
            INSERT @fail VALUES (N'STAGE_OUTSIDE_CYCLE');
        IF EXISTS (SELECT 1 FROM sel.CycleStage a
                   JOIN sel.CycleStage b ON b.CycleProcessId = a.CycleProcessId AND b.CycleStageId <> a.CycleStageId
                   JOIN sel.CycleProcess p ON p.CycleProcessId = a.CycleProcessId
                   WHERE p.CycleId = @CycleId AND a.SortOrder < b.SortOrder
                     AND a.EndDate IS NOT NULL AND b.StartDate IS NOT NULL AND a.EndDate > b.StartDate)
            INSERT @fail VALUES (N'STAGE_OVERLAP');
        IF EXISTS (SELECT 1 FROM sel.CycleStage s
                   JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                   WHERE p.CycleId = @CycleId AND s.PerformerLevelValueId IS NULL)
            INSERT @fail VALUES (N'STAGE_NO_PERFORMER');
    END;

    /* Up to five to-dos, each with the step that fixes it. */
    SELECT TOP (CAST(ISNULL(cfg.fn_SettingNum(N'VALIDATION_MAX_SHOWN'), 5) AS int))
           v.ValidationRuleId, v.RuleCode, v.StepNo, v.Sentence, v.Severity, v.SortOrder,
           StepCaption = (SELECT Caption FROM sel.WizardStep w WHERE w.StepNo = v.StepNo)
    FROM sel.ValidationRule v
    JOIN @fail f ON f.RuleCode = v.RuleCode
    WHERE v.IsActive = 1
    ORDER BY v.SortOrder, v.RuleCode;

    IF @TodoOnly = 1 RETURN;

    /* The progress meter: "3 of 5 set · 1 skipped · still to do: Eligible pool." */
    SELECT TotalBlocking = (SELECT COUNT(*) FROM sel.ValidationRule v JOIN @fail f ON f.RuleCode = v.RuleCode
                            WHERE v.IsActive = 1 AND v.Severity = N'BLOCK'),
           IsReadyToOpen = CONVERT(bit, CASE WHEN EXISTS (SELECT 1 FROM sel.ValidationRule v JOIN @fail f ON f.RuleCode = v.RuleCode
                                             WHERE v.IsActive = 1 AND v.Severity = N'BLOCK')
                                THEN 0 ELSE 1 END),
           StepsSet     = (SELECT COUNT(*) FROM sel.fn_CycleConfiguredTracks(@CycleId) WHERE IsSet = 1),
           StepsTotal   = (SELECT COUNT(*) FROM sel.fn_CycleConfiguredTracks(@CycleId)),
           StepsSkipped = (SELECT COUNT(*) FROM @skipped);

    /* The five tracks, so the design list can show which step is missing without a number. */
    SELECT TrackCode, IsSet, SortOrder FROM sel.fn_CycleConfiguredTracks(@CycleId) ORDER BY SortOrder;
END
GO
PRINT '  sel.usp_Cycle_Validate            applied';
GO

/* =====================================================================================
   sel.usp_Cycle_AutoSchedule — setting both dates gives every undated process and stage
   its share of the window, in order.  A hand-set window is never overwritten.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_AutoSchedule
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
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId;
        RETURN;
    END;

    DECLARE @start date, @end date;
    SELECT @start = StartDate, @end = EndDate FROM sel.Cycle WHERE CycleId = @CycleId;

    IF @start IS NULL OR @end IS NULL
    BEGIN
        SET @Problem = N'Set both a start and an end date before the stages can be scheduled.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleProcessId;
        RETURN;
    END;

    BEGIN TRAN;

    DECLARE @days int = DATEDIFF(DAY, @start, @end);
    DECLARE @procCount int = (SELECT COUNT(*) FROM sel.CycleProcess WHERE CycleId = @CycleId AND (StartDate IS NULL OR EndDate IS NULL));

    /* Undated processes take an equal share of the window, in order. */
    IF @procCount > 0
    BEGIN
        ;WITH p AS
        (
            SELECT CycleProcessId, rn = ROW_NUMBER() OVER (ORDER BY SortOrder, CycleProcessId),
                   n = COUNT(*) OVER ()
            FROM sel.CycleProcess WHERE CycleId = @CycleId AND (StartDate IS NULL OR EndDate IS NULL)
        )
        UPDATE cp
           SET StartDate = DATEADD(DAY, CAST(@days * (p.rn - 1.0) / p.n AS int), @start),
               EndDate   = DATEADD(DAY, CAST(@days * (p.rn * 1.0)  / p.n AS int) - 1, @start)
        FROM sel.CycleProcess cp JOIN p ON p.CycleProcessId = cp.CycleProcessId;
    END;

    /* Each process's undated stages split that process's window, in order. */
    ;WITH s AS
    (
        SELECT st.CycleStageId, st.CycleProcessId,
               rn = ROW_NUMBER() OVER (PARTITION BY st.CycleProcessId ORDER BY st.SortOrder, st.CycleStageId),
               n  = COUNT(*)     OVER (PARTITION BY st.CycleProcessId),
               pStart = cp.StartDate, pDays = DATEDIFF(DAY, cp.StartDate, cp.EndDate)
        FROM sel.CycleStage st
        JOIN sel.CycleProcess cp ON cp.CycleProcessId = st.CycleProcessId
        WHERE cp.CycleId = @CycleId AND (st.StartDate IS NULL OR st.EndDate IS NULL)
          AND cp.StartDate IS NOT NULL AND cp.EndDate IS NOT NULL
    )
    UPDATE cs
       SET StartDate = DATEADD(DAY, CAST(s.pDays * (s.rn - 1.0) / s.n AS int), s.pStart),
           EndDate   = DATEADD(DAY, CAST(s.pDays * (s.rn * 1.0)  / s.n AS int) - 1, s.pStart)
    FROM sel.CycleStage cs JOIN s ON s.CycleStageId = cs.CycleStageId;

    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId);
    EXEC audit.usp_Log @TableName = N'sel.CycleStage', @KeyText = @keyText,
                       @ActionCode = N'AUTOSCHEDULE', @LoginName = @LoginName;

    SELECT p.CycleProcessId, p.Name AS ProcessName, p.StartDate AS ProcessStart, p.EndDate AS ProcessEnd,
           s.CycleStageId, s.Name AS StageName, s.StartDate, s.EndDate, s.SortOrder
    FROM sel.CycleProcess p
    LEFT JOIN sel.CycleStage s ON s.CycleProcessId = p.CycleProcessId
    WHERE p.CycleId = @CycleId
    ORDER BY p.SortOrder, s.SortOrder;
END
GO
PRINT '  sel.usp_Cycle_AutoSchedule        applied';
GO

/* =====================================================================================
   sel.usp_Cycle_Open — resolve the pool, write it as a snapshot, start the first stage,
   and make the draft Active permanently.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_Open
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL,
    @Problem   nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    SET @Problem = NULL;

    IF sec.fn_CanEditCycle(@LoginName, @CycleId) = 0
    BEGIN
        SET @Problem = sec.fn_CycleEditRefusal(@LoginName, @CycleId);
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    IF sel.fn_CycleStatusCode(@CycleId) <> N'DRAFT'
    BEGIN
        SET @Problem = N'Only a draft can be opened. This cycle is already '
                     + LOWER(ISNULL(sel.fn_CycleStatusCode(@CycleId), N'unknown')) + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    /* The design must pass its own validation first. */
    /* Re-run the validation into a table so the refusal names the real count.  The same
       procedure the wizard calls, asked for its to-do list alone. */
    CREATE TABLE #todo (ValidationRuleId int, RuleCode nvarchar(60), StepNo int,
                        Sentence nvarchar(600), Severity nvarchar(20), SortOrder int,
                        StepCaption nvarchar(120));
    INSERT #todo EXEC sel.usp_Cycle_Validate @LoginName = @LoginName, @CycleId = @CycleId,
                                             @AsOf = @AsOf, @TodoOnly = 1;

    DECLARE @blocking int = (SELECT COUNT(*) FROM #todo WHERE Severity = N'BLOCK');
    IF @blocking > 0
    BEGIN
        SET @Problem = CONVERT(nvarchar(10), @blocking) + N' thing'
                     + CASE WHEN @blocking = 1 THEN N' is' ELSE N's are' END
                     + N' unfinished, so this cycle cannot be opened yet.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        DROP TABLE #todo;
        RETURN;
    END;
    DROP TABLE #todo;

    DECLARE @obj nvarchar(300) = sel.fn_MappedObject(N'ROSTER');
    DECLARE @keyCol nvarchar(128) = (SELECT KeyColumn FROM sel.TableMapping WHERE SourceKey = N'ROSTER');
    IF @obj IS NULL
    BEGIN
        SET @Problem = cfg.fn_Message(N'ROSTER_UNMAPPED');
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    DECLARE @where nvarchar(max), @p nvarchar(400);
    EXEC sel.usp_Criteria_BuildWhere @CycleId = @CycleId, @Alias = N'rs', @AsOf = @AsOf,
                                     @Where = @where OUTPUT, @Problem = @p OUTPUT;
    IF @p IS NOT NULL
    BEGIN
        SET @Problem = @p;
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    BEGIN TRAN;

    /* The eligible pool.  Note this resolves across the WHOLE organisation, not the
       opener's scope: the snapshot is the cycle's, not one viewer's.  Row-level security
       is applied on every read of it afterwards. */
    DECLARE @sql nvarchar(max) = N'
        INSERT sel.CycleCandidate (CycleId, PersonnelNo, SourceCode, OrgCode, AddedByLogin)
        SELECT DISTINCT @CycleId, e.PersonnelNo, N''ELIGIBLE'', e.OrgCode, @LoginName
        FROM ' + @obj + N' rs
        JOIN sel.Employee e ON e.PersonnelNo = CONVERT(nvarchar(30), rs.' + QUOTENAME(@keyCol) + N')
        WHERE ' + @where + N'
          AND NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                          WHERE cc.CycleId = @CycleId AND cc.PersonnelNo = e.PersonnelNo);';

    EXEC sp_executesql @sql, N'@CycleId int, @LoginName nvarchar(128)',
         @CycleId = @CycleId, @LoginName = @LoginName;

    /* The existing pool carried in: matched on end year - 1 = pool year and the successor
       suffix.  A carried person is marked so the source tag persists through every stage. */
    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @CycleId AND ExistingPoolCode IS NOT NULL)
       AND ISNULL((SELECT IsMapped FROM sel.TableMapping WHERE SourceKey = N'POOL'), 0) = 1
    BEGIN
        DECLARE @poolObj nvarchar(300) = sel.fn_MappedObject(N'POOL');
        DECLARE @poolKey nvarchar(128) = (SELECT KeyColumn  FROM sel.TableMapping WHERE SourceKey = N'POOL');
        DECLARE @poolItem nvarchar(128) = (SELECT ItemColumn FROM sel.TableMapping WHERE SourceKey = N'POOL');
        DECLARE @poolCode nvarchar(60) = (SELECT ExistingPoolCode FROM sel.Cycle WHERE CycleId = @CycleId);
        DECLARE @poolYear int = (SELECT YEAR(EndDate) - 1 FROM sel.Cycle WHERE CycleId = @CycleId);

        DECLARE @psql nvarchar(max) = N'
            INSERT sel.CycleCandidate (CycleId, PersonnelNo, SourceCode, OrgCode, AddedByLogin)
            SELECT DISTINCT @CycleId, e.PersonnelNo, N''EXISTING POOL'', e.OrgCode, @LoginName
            FROM ' + @poolObj + N' pm
            JOIN sel.Employee e ON e.PersonnelNo = CONVERT(nvarchar(30), pm.' + QUOTENAME(@poolKey) + N')
            WHERE pm.' + QUOTENAME(@poolItem) + N' = @poolCode
              AND NOT EXISTS (SELECT 1 FROM sel.CycleCandidate cc
                              WHERE cc.CycleId = @CycleId AND cc.PersonnelNo = e.PersonnelNo);';
        BEGIN TRY
            EXEC sp_executesql @psql,
                 N'@CycleId int, @LoginName nvarchar(128), @poolCode nvarchar(60)',
                 @CycleId = @CycleId, @LoginName = @LoginName, @poolCode = @poolCode;
        END TRY
        BEGIN CATCH
            /* A carry-in that cannot be read is a load exception, not a silent omission. */
            INSERT stg.LoadException (SourceKey, SourceTable, KeyText, ReasonCode, ReasonText)
            VALUES (N'POOL', @poolObj, @poolCode, N'CARRY_IN_FAILED',
                    N'Last year''s pool could not be carried into this cycle: ' + ERROR_MESSAGE());
        END CATCH;
    END;

    /* The trace: for each pooled person, which criterion was satisfied and with what. */
    INSERT sel.CycleCandidateTrace (CycleId, PersonnelNo, CriterionId, SetLabel, FieldName,
                                    OperatorName, TestedValue, ActualValue, Passed)
    SELECT cc.CycleId, cc.PersonnelNo, c.CriterionId, cs.SetLabel, f.FieldName, o.Name,
           CASE WHEN o.Arity = 0 THEN NULL
                WHEN o.Arity = 1 THEN c.Value1
                ELSE c.Value1 + N' and ' + ISNULL(c.Value2, N'') END,
           NULL, 1
    FROM sel.CycleCandidate cc
    JOIN sel.CycleCriterionSet cs ON cs.CycleId = cc.CycleId
    JOIN sel.CycleCriterion c ON c.CriterionSetId = cs.CriterionSetId
    JOIN sel.RosterField f ON f.RosterFieldId = c.RosterFieldId
    JOIN cfg.Operator o ON o.OperatorCode = c.OperatorCode
    WHERE cc.CycleId = @CycleId AND cc.SourceCode = N'ELIGIBLE';

    /* Every process starts with the whole pool. */
    INSERT sel.ProcessCandidate (CycleProcessId, PersonnelNo, SourceCode, AddedByLogin)
    SELECT p.CycleProcessId, cc.PersonnelNo, cc.SourceCode, @LoginName
    FROM sel.CycleProcess p
    JOIN sel.CycleCandidate cc ON cc.CycleId = p.CycleId
    WHERE p.CycleId = @CycleId
      AND NOT EXISTS (SELECT 1 FROM sel.ProcessCandidate pc
                      WHERE pc.CycleProcessId = p.CycleProcessId AND pc.PersonnelNo = cc.PersonnelNo);

    DECLARE @count int = (SELECT COUNT(*) FROM sel.CycleCandidate WHERE CycleId = @CycleId);

    UPDATE sel.Cycle
       SET StatusValueId = cfg.fn_DomainValueId(N'CYCLE_STATUS', N'ACTIVE'),
           OpenedOnUtc = SYSUTCDATETIME(),
           PoolResolvedOnUtc = SYSUTCDATETIME(),
           PoolCount = @count
    WHERE CycleId = @CycleId;

    COMMIT;

    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @CycleId);
    EXEC audit.usp_Log @TableName = N'sel.Cycle', @KeyText = @keyText,
                       @ActionCode = N'OPEN', @LoginName = @LoginName;

    SELECT CycleId = @CycleId, PoolCount = @count,
           FirstStageId = (SELECT TOP (1) s.CycleStageId
                           FROM sel.CycleStage s
                           JOIN sel.CycleProcess p ON p.CycleProcessId = s.CycleProcessId
                           WHERE p.CycleId = @CycleId
                           ORDER BY p.SortOrder, s.SortOrder);
END
GO
PRINT '  sel.usp_Cycle_Open                applied';
GO

/* =====================================================================================
   sel.usp_Cycle_Copy — carries design, criteria, levels, processes, frameworks and pool
   rules forward as a new Draft.  It never carries the snapshot or the decisions.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Cycle_Copy
    @LoginName   nvarchar(128),
    @SourceCycleId int,
    @NewCode     nvarchar(40),
    @NewName     nvarchar(300),
    @Problem     nvarchar(400) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Problem = NULL;

    /* Copying reads the source and writes a new design, so the source may be Closed —
       that is the whole point of "a closed cycle is never changed, only copied". */
    IF sec.fn_ScreenAccess(@LoginName, N'/Selection/CycleSetup/') < 2
    BEGIN
        SET @Problem = cfg.fn_Message(N'READONLY_REFUSAL');
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleId = @SourceCycleId)
    BEGIN
        SET @Problem = N'That cycle no longer exists, so there is nothing to copy.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM sel.Cycle WHERE CycleCode = @NewCode)
    BEGIN
        SET @Problem = N'There is already a cycle with the code ' + @NewCode + N'.';
        SELECT TOP (0) CAST(NULL AS int) AS CycleId;
        RETURN;
    END;

    BEGIN TRAN;

    INSERT sel.Cycle (CycleCode, Name, StartDate, EndDate, StatusValueId, OwnerLogin, DelegateLogin,
                      Notes, IncumbentSuffix, SuccessorSuffix, ExistingPoolCode, ActiveMembersOnly,
                      RecipeId, CreatedByLogin)
    SELECT @NewCode, @NewName, NULL, NULL,
           cfg.fn_DomainValueId(N'CYCLE_STATUS', N'DRAFT'),
           @LoginName, DelegateLogin, Notes, IncumbentSuffix, SuccessorSuffix,
           ExistingPoolCode, ActiveMembersOnly, RecipeId, @LoginName
    FROM sel.Cycle WHERE CycleId = @SourceCycleId;

    DECLARE @newId int = SCOPE_IDENTITY();

    INSERT sel.CycleJobSuffix (CycleId, RoleCode, JobSuffix, SuffixDesc)
    SELECT @newId, RoleCode, JobSuffix, SuffixDesc FROM sel.CycleJobSuffix WHERE CycleId = @SourceCycleId;

    /* Criteria, with their sets, keeping the labels and the joins. */
    DECLARE @setMap TABLE (OldId int, NewId int);
    MERGE sel.CycleCriterionSet AS t
    USING (SELECT CriterionSetId, SetLabel, SetModeValueId, SetJoinValueId, SortOrder
           FROM sel.CycleCriterionSet WHERE CycleId = @SourceCycleId) AS s
       ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (CycleId, SetLabel, SetModeValueId, SetJoinValueId, SortOrder)
        VALUES (@newId, s.SetLabel, s.SetModeValueId, s.SetJoinValueId, s.SortOrder)
    OUTPUT s.CriterionSetId, inserted.CriterionSetId INTO @setMap (OldId, NewId);

    INSERT sel.CycleCriterion (CriterionSetId, RosterFieldId, OperatorCode, Value1, Value2, SortOrder)
    SELECT m.NewId, c.RosterFieldId, c.OperatorCode, c.Value1, c.Value2, c.SortOrder
    FROM sel.CycleCriterion c
    JOIN @setMap m ON m.OldId = c.CriterionSetId;

    INSERT sel.CycleFramework (CycleId, DevFrameworkId)
    SELECT @newId, DevFrameworkId FROM sel.CycleFramework WHERE CycleId = @SourceCycleId;

    INSERT sel.CycleReadiness (CycleId, LevelCode, Name, ThresholdPct, SortOrder)
    SELECT @newId, LevelCode, Name, ThresholdPct, SortOrder FROM sel.CycleReadiness WHERE CycleId = @SourceCycleId;

    INSERT sel.CycleRequirement (CycleId, DevEventId, LevelCode, Weight, IsMust, SortOrder)
    SELECT @newId, DevEventId, LevelCode, Weight, IsMust, SortOrder FROM sel.CycleRequirement WHERE CycleId = @SourceCycleId;

    /* Processes and their stages, undated: the new design sets its own window. */
    DECLARE @procMap TABLE (OldId int, NewId int);
    MERGE sel.CycleProcess AS t
    USING (SELECT CycleProcessId, ProcessTypeCode, Name, SortOrder
           FROM sel.CycleProcess WHERE CycleId = @SourceCycleId) AS s
       ON 1 = 0
    WHEN NOT MATCHED THEN
        INSERT (CycleId, ProcessTypeCode, Name, StartDate, EndDate, SortOrder)
        VALUES (@newId, s.ProcessTypeCode, s.Name, NULL, NULL, s.SortOrder)
    OUTPUT s.CycleProcessId, inserted.CycleProcessId INTO @procMap (OldId, NewId);

    INSERT sel.CycleStage (CycleProcessId, StageKindCode, Name, StartDate, EndDate, PerformerLevelValueId, SortOrder)
    SELECT m.NewId, s.StageKindCode, s.Name, NULL, NULL, s.PerformerLevelValueId, s.SortOrder
    FROM sel.CycleStage s JOIN @procMap m ON m.OldId = s.CycleProcessId;

    INSERT sel.CycleSkippedStep (CycleId, StepNo, SkippedByLogin)
    SELECT @newId, StepNo, @LoginName FROM sel.CycleSkippedStep WHERE CycleId = @SourceCycleId;

    COMMIT;

    DECLARE @after nvarchar(max) = (SELECT CycleId, CycleCode, Name FROM sel.Cycle WHERE CycleId = @newId
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @keyText nvarchar(200) = CONVERT(nvarchar(20), @newId);
    EXEC audit.usp_Log @TableName = N'sel.Cycle', @KeyText = @keyText, @ActionCode = N'COPY',
                       @AfterJson = @after, @LoginName = @LoginName;

    SELECT CycleId = @newId, CycleCode = @NewCode, Name = @NewName,
           CopiedFrom = @SourceCycleId;
END
GO
PRINT '  sel.usp_Cycle_Copy                applied';
GO

PRINT '== 08_pool_and_open complete =========================================';
GO
