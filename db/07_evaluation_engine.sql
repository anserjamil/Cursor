/* =====================================================================================
   07_evaluation_engine.sql  —  whether one person meets one requirement
   -------------------------------------------------------------------------------------
   One worker decides whether a person meets an item, and everything calls it: the profile
   ladder, the pool coverage percentages, the readiness distribution and the IDP's list of
   open obligations.  The four can never disagree because there is only one answer.

       itemMet(person, itemCode) -> { met, why, value, target, viaCode }

   The rules that make it correct:

   1. Candidate codes are the item itself plus every code equivalent to it.
   2. For EACH code, load THAT code's own event, its own rule and its own mapped source.
      An equivalent may live in a different table with different columns; judging it by
      the main item's rule reads the wrong field and returns a wrong answer with no error.
      This is the single most important correctness rule in the product.
   3. Flag mode: met when any candidate row passes its OWN rule; the code that satisfied
      it is returned so the UI can say "via ASM-360-02".
   4. Sum mode: each candidate row is filtered by its OWN conditions, the measure is
      summed over the survivors, and it is met when the total reaches the floor.
   5. One row against one rule: each set is evaluated independently (all / any / none),
      then the sets are folded left to right with their joins (and / or / except).
      A condition with no field chosen fails ITS OWN condition, not the others.
   6. why is not optional.  Return the reason, not the verdict.

   And the performance rule: the evaluation is set-based over people.  One statement per
   candidate code answers the whole pool.  Nothing here is ever called inside a loop over
   people — that shape is 240,000 evaluations to answer one screen.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 07_evaluation_engine ==============================================';
GO

/* =====================================================================================
   Escaping and predicate building
   ===================================================================================== */

/* cfg.fn_EscapeLiteral — a value as a safe SQL literal.  Nothing concatenates a raw
   user value into dynamic SQL anywhere in this database; it comes through here.        */
CREATE OR ALTER FUNCTION cfg.fn_EscapeLiteral (@Value nvarchar(400))
RETURNS nvarchar(1000)
AS
BEGIN
    IF @Value IS NULL RETURN N'NULL';
    RETURN N'N''' + REPLACE(@Value, N'''', N'''''') + N'''';
END
GO
PRINT '  cfg.fn_EscapeLiteral              applied';
GO

/* cfg.fn_EscapeList — a comma separated value as a safe, quoted IN list. */
CREATE OR ALTER FUNCTION cfg.fn_EscapeList (@Csv nvarchar(400))
RETURNS nvarchar(max)
AS
BEGIN
    IF @Csv IS NULL OR LTRIM(RTRIM(@Csv)) = N'' RETURN N'NULL';

    DECLARE @out nvarchar(max) =
        STUFF((SELECT N', ' + cfg.fn_EscapeLiteral(LTRIM(RTRIM(value)))
               FROM STRING_SPLIT(@Csv, N',')
               WHERE LTRIM(RTRIM(value)) <> N''
               FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'');

    RETURN ISNULL(@out, N'NULL');
END
GO
PRINT '  cfg.fn_EscapeList                 applied';
GO

/* cfg.fn_BuildPredicate — one condition as a SQL predicate, from the operator's own
   template.  The only place the SQL shape of an operator is decided; there is no
   if (op = '>=') chain anywhere in this product.

   A number or a date is re-emitted from its parsed value, never from the raw text, so a
   value that is not a number cannot become SQL.  Anything else is quoted.               */
CREATE OR ALTER FUNCTION cfg.fn_BuildPredicate
(
    @ColumnExpr   nvarchar(1000),
    @OperatorCode nvarchar(30),
    @Value1       nvarchar(400),
    @Value2       nvarchar(400),
    @DataType     nvarchar(20),
    @AsOf         date
)
RETURNS nvarchar(max)
AS
BEGIN
    IF @ColumnExpr IS NULL OR @OperatorCode IS NULL RETURN N'(1 = 0)';

    DECLARE @template nvarchar(400), @arity tinyint;
    SELECT @template = SqlTemplate, @arity = Arity
    FROM cfg.Operator WHERE OperatorCode = @OperatorCode AND IsActive = 1;

    /* An operator that is not in the table is not an operator. */
    IF @template IS NULL RETURN N'(1 = 0)';

    /* The number of values must match the operator's arity. */
    IF @arity >= 1 AND (@Value1 IS NULL OR LTRIM(RTRIM(@Value1)) = N'') RETURN N'(1 = 0)';
    IF @arity >= 2 AND (@Value2 IS NULL OR LTRIM(RTRIM(@Value2)) = N'') RETURN N'(1 = 0)';

    DECLARE @l1 nvarchar(max), @l2 nvarchar(max);

    IF @DataType = N'number'
    BEGIN
        IF @arity >= 1 AND TRY_CONVERT(decimal(38,10), @Value1) IS NULL RETURN N'(1 = 0)';
        IF @arity >= 2 AND TRY_CONVERT(decimal(38,10), @Value2) IS NULL RETURN N'(1 = 0)';
        SET @l1 = CONVERT(nvarchar(60), TRY_CONVERT(decimal(38,10), @Value1));
        SET @l2 = CONVERT(nvarchar(60), TRY_CONVERT(decimal(38,10), @Value2));
    END
    ELSE IF @DataType = N'date'
    BEGIN
        IF @arity >= 1 AND TRY_CONVERT(date, @Value1) IS NULL RETURN N'(1 = 0)';
        IF @arity >= 2 AND TRY_CONVERT(date, @Value2) IS NULL RETURN N'(1 = 0)';
        SET @l1 = N'CONVERT(date, ''' + CONVERT(nvarchar(10), TRY_CONVERT(date, @Value1), 23) + N''', 23)';
        SET @l2 = N'CONVERT(date, ''' + CONVERT(nvarchar(10), TRY_CONVERT(date, @Value2), 23) + N''', 23)';
    END
    ELSE
    BEGIN
        SET @l1 = cfg.fn_EscapeLiteral(@Value1);
        SET @l2 = cfg.fn_EscapeLiteral(@Value2);
    END;

    DECLARE @asOfLiteral nvarchar(80) =
        N'CONVERT(date, ''' + CONVERT(nvarchar(10), ISNULL(@AsOf, CAST(SYSUTCDATETIME() AS date)), 23) + N''', 23)';

    DECLARE @sql nvarchar(max) = @template;
    SET @sql = REPLACE(@sql, N'{col}',   @ColumnExpr);
    SET @sql = REPLACE(@sql, N'{asof}',  @asOfLiteral);
    SET @sql = REPLACE(@sql, N'{list1}', cfg.fn_EscapeList(@Value1));
    SET @sql = REPLACE(@sql, N'{like1}', cfg.fn_EscapeLiteral(N'%' + ISNULL(@Value1, N'') + N'%'));
    SET @sql = REPLACE(@sql, N'{v1}',    ISNULL(@l1, N'NULL'));
    SET @sql = REPLACE(@sql, N'{v2}',    ISNULL(@l2, N'NULL'));

    RETURN N'(' + @sql + N')';
END
GO
PRINT '  cfg.fn_BuildPredicate             applied';
GO

/* sel.fn_ConditionColumnExpr — how one field is read from one evidence row.
   A physical column is read directly; a learned field is read through
   sel.EmployeeRecordDetail, so a rule may name a column this schema never anticipated
   without needing a migration.                                                          */
CREATE OR ALTER FUNCTION sel.fn_ConditionColumnExpr
(
    @EvidenceSourceId int,
    @FieldName        nvarchar(128),
    @Alias            nvarchar(20),
    @DataType         nvarchar(20)
)
RETURNS nvarchar(1000)
AS
BEGIN
    IF @FieldName IS NULL OR LTRIM(RTRIM(@FieldName)) = N'' RETURN NULL;

    DECLARE @isPhysical bit, @appSchema nvarchar(128), @appTable nvarchar(128);
    SELECT @isPhysical = c.IsPhysical
    FROM sel.EvidenceSourceColumn c
    WHERE c.EvidenceSourceId = @EvidenceSourceId AND c.ColumnName = @FieldName;

    SELECT @appSchema = AppSchema, @appTable = AppTable
    FROM sel.EvidenceSource WHERE EvidenceSourceId = @EvidenceSourceId;

    /* A field the editor has never seen is treated as physical if the table really has
       it, and otherwise as a detail key. */
    IF @isPhysical IS NULL
        SET @isPhysical = CASE WHEN EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                                            WHERE TABLE_SCHEMA = @appSchema
                                              AND TABLE_NAME = @appTable
                                              AND COLUMN_NAME = @FieldName)
                               THEN 1 ELSE 0 END;

    IF @isPhysical = 1
        RETURN @Alias + N'.' + QUOTENAME(@FieldName);

    /* Only the record-based source carries a detail table. */
    IF @appTable <> N'EmployeeRecord' RETURN NULL;

    RETURN N'(SELECT TOP (1) '
         + CASE @DataType WHEN N'number' THEN N'd.ValueNum'
                          WHEN N'date'   THEN N'd.ValueDate'
                          ELSE N'd.ValueText' END
         + N' FROM sel.EmployeeRecordDetail d WHERE d.EmployeeRecordId = ' + @Alias
         + N'.EmployeeRecordId AND d.FieldName = ' + cfg.fn_EscapeLiteral(@FieldName) + N')';
END
GO
PRINT '  sel.fn_ConditionColumnExpr        applied';
GO

/* =====================================================================================
   sel.usp_Event_BuildWhere — one event's rule as a SQL predicate over one evidence row
   -------------------------------------------------------------------------------------
   Each set is evaluated independently, then the sets are folded left to right with their
   joins.  "except" is "and not".  An event with no sets returns the kind's default.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Event_BuildWhere
    @DevEventId int,
    @Alias      nvarchar(20) = N'r',
    @AsOf       date = NULL,
    @Where      nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    SET @Where = NULL;

    DECLARE @kind nvarchar(30), @sourceId int, @statusCol nvarchar(128), @passValue nvarchar(120),
            @evalMode nvarchar(20), @eventPass nvarchar(120);

    SELECT @kind = e.KindCode, @eventPass = e.PassValue FROM sel.DevEvent e WHERE e.DevEventId = @DevEventId;
    IF @kind IS NULL BEGIN SET @Where = N'(1 = 0)'; RETURN; END;

    SELECT @evalMode = EvalModeCode FROM sel.RequirementKind WHERE KindCode = @kind;
    SELECT @sourceId = EvidenceSourceId, @statusCol = StatusColumn, @passValue = PassValue
    FROM sel.EvidenceSource WHERE KindCode = @kind;

    IF NOT EXISTS (SELECT 1 FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId)
    BEGIN
        /* No conditions: follow the kind's default. */
        IF @evalMode = N'SUM'
        BEGIN
            SET @Where = N'(1 = 1)';     -- every row of this person's coverage counts
            RETURN;
        END;

        DECLARE @pass nvarchar(120) = ISNULL(@eventPass, @passValue);
        IF @statusCol IS NULL OR @pass IS NULL
            SET @Where = N'(1 = 1)';
        ELSE
            SET @Where = N'(' + @Alias + N'.' + QUOTENAME(@statusCol) + N' = '
                       + cfg.fn_EscapeLiteral(@pass) + N')';
        RETURN;
    END;

    /* Build each set, then fold. */
    DECLARE @folded nvarchar(max) = NULL;
    DECLARE @setId int, @setMode nvarchar(60), @setJoin nvarchar(60), @first bit = 1;

    DECLARE setCur CURSOR LOCAL FAST_FORWARD FOR
        SELECT cs.SetId, mv.ValueCode, jv.ValueCode
        FROM sel.DevEventConditionSet cs
        JOIN cfg.DomainValue mv ON mv.DomainValueId = cs.SetModeValueId
        LEFT JOIN cfg.DomainValue jv ON jv.DomainValueId = cs.SetJoinValueId
        WHERE cs.DevEventId = @DevEventId
        ORDER BY cs.SortOrder, cs.SetLabel;

    OPEN setCur;
    FETCH NEXT FROM setCur INTO @setId, @setMode, @setJoin;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* Every condition in the set, each built from its own field and operator.
           A condition with no field chosen becomes (1 = 0): it fails itself, and
           because the set combines them it does not reach into the others.           */
        DECLARE @parts nvarchar(max) =
            STUFF((SELECT CASE WHEN @setMode = N'ALL' THEN N' AND ' ELSE N' OR ' END
                        + cfg.fn_BuildPredicate(
                              sel.fn_ConditionColumnExpr(@sourceId, c.FieldName, @Alias,
                                  ISNULL(esc.DataType, N'text')),
                              c.OperatorCode, c.Value1, c.Value2,
                              ISNULL(esc.DataType, N'text'), @AsOf)
                   FROM sel.DevEventCondition c
                   LEFT JOIN sel.EvidenceSourceColumn esc
                          ON esc.EvidenceSourceId = @sourceId AND esc.ColumnName = c.FieldName
                   WHERE c.SetId = @setId
                   ORDER BY c.SortOrder, c.ConditionId
                   FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'),
                  1, CASE WHEN @setMode = N'ALL' THEN 5 ELSE 4 END, N'');

        DECLARE @setSql nvarchar(max);
        IF @parts IS NULL
            /* A set with no conditions holds for every row rather than for none: an
               empty set is an unfinished edit, not a rule that excludes everybody. */
            SET @setSql = N'(1 = 1)';
        ELSE IF @setMode = N'NONE'
            SET @setSql = N'(NOT (' + @parts + N'))';
        ELSE
            SET @setSql = N'(' + @parts + N')';

        IF @first = 1
        BEGIN
            SET @folded = @setSql;
            SET @first = 0;
        END
        ELSE
            SET @folded = N'(' + @folded +
                CASE ISNULL(@setJoin, N'AND')
                     WHEN N'OR'     THEN N' OR '
                     WHEN N'EXCEPT' THEN N' AND NOT '
                     ELSE N' AND ' END
                + @setSql + N')';

        FETCH NEXT FROM setCur INTO @setId, @setMode, @setJoin;
    END;

    CLOSE setCur; DEALLOCATE setCur;

    SET @Where = ISNULL(@folded, N'(1 = 1)');
END
GO
PRINT '  sel.usp_Event_BuildWhere          applied';
GO

/* =====================================================================================
   sel.usp_Item_ResolveMet_Into — the worker
   -------------------------------------------------------------------------------------
   The caller creates #scope (PersonnelNo) and #met, and this appends one row per person
   in scope.  It iterates over candidate CODES (a handful) and is set-based over PEOPLE
   (the expensive dimension): one statement per code answers the whole pool.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Item_ResolveMet_Into
    @ItemCode nvarchar(60),
    @AsOf     date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    /* Per-code, per-person outcome, before the candidate codes are folded together. */
    CREATE TABLE #code_hit
    (
        PersonnelNo nvarchar(30)  NOT NULL,
        ViaCode     nvarchar(60)  NOT NULL,
        Passed      bit           NOT NULL,
        HasRow      bit           NOT NULL,
        NumValue    decimal(18,4) NULL,
        TextValue   nvarchar(200) NULL,
        Target      decimal(18,4) NULL
    );

    DECLARE @code nvarchar(60), @isMain bit;
    DECLARE codeCur CURSOR LOCAL FAST_FORWARD FOR
        SELECT ItemCode, IsMain FROM sel.fn_ItemCandidateCodes(@ItemCode) ORDER BY IsMain DESC, ItemCode;

    OPEN codeCur;
    FETCH NEXT FROM codeCur INTO @code, @isMain;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        /* --- this code's OWN event, rule and mapped source ------------------------- */
        DECLARE @evId int, @kind nvarchar(30), @evalMode nvarchar(20), @floor decimal(18,4),
                @appSchema nvarchar(128), @appTable nvarchar(128), @itemCol nvarchar(128),
                @measureCol nvarchar(128), @statusCol nvarchar(128), @isMapped bit;

        SELECT @evId = NULL, @kind = NULL, @evalMode = NULL, @floor = NULL,
               @appSchema = NULL, @appTable = NULL, @itemCol = NULL,
               @measureCol = NULL, @statusCol = NULL, @isMapped = NULL;

        SELECT TOP (1) @evId = e.DevEventId, @kind = e.KindCode, @floor = e.SumFloor
        FROM sel.DevEvent e
        WHERE e.ItemCode = @code AND e.IsActive = 1
        ORDER BY e.DevEventId;

        /* An equivalent code may have no event of its own; fall back to the catalogue
           entry's kind so its evidence is still read with that kind's default rule. */
        IF @kind IS NULL
            SELECT TOP (1) @kind = ci.KindCode FROM sel.CatalogItem ci
            WHERE ci.ItemCode = @code ORDER BY ci.CatalogItemId;

        IF @kind IS NOT NULL
        BEGIN
            SELECT @evalMode = EvalModeCode FROM sel.RequirementKind WHERE KindCode = @kind;
            SELECT @appSchema = AppSchema, @appTable = AppTable, @itemCol = ItemColumn,
                   @measureCol = MeasureColumn, @statusCol = StatusColumn, @isMapped = IsMapped
            FROM sel.EvidenceSource WHERE KindCode = @kind;
        END;

        /* An unmapped source can never be met — and that is said in words later, never
           rendered as a silent zero. */
        IF @kind IS NOT NULL AND ISNULL(@isMapped, 0) = 1
        BEGIN
            DECLARE @where nvarchar(max) = N'(1 = 1)';
            IF @evId IS NOT NULL
                EXEC sel.usp_Event_BuildWhere @DevEventId = @evId, @Alias = N'r',
                                              @AsOf = @AsOf, @Where = @where OUTPUT;
            ELSE IF @statusCol IS NOT NULL
                SELECT @where = N'(r.' + QUOTENAME(@statusCol) + N' = '
                              + cfg.fn_EscapeLiteral(s.PassValue) + N')'
                FROM sel.EvidenceSource s WHERE s.KindCode = @kind AND s.PassValue IS NOT NULL;

            DECLARE @sql nvarchar(max);
            DECLARE @obj nvarchar(300) = QUOTENAME(@appSchema) + N'.' + QUOTENAME(@appTable);

            IF @evalMode = N'SUM'
            BEGIN
                /* Each candidate row is filtered by its own conditions, and the measure
                   is summed over the survivors.  One statement, whole pool.            */
                SET @sql = N'
                INSERT #code_hit (PersonnelNo, ViaCode, Passed, HasRow, NumValue, TextValue, Target)
                SELECT s.PersonnelNo, @code,
                       CASE WHEN ISNULL(x.Total, 0) >= @floor THEN 1 ELSE 0 END,
                       CASE WHEN x.RowsSeen > 0 THEN 1 ELSE 0 END,
                       ISNULL(x.Total, 0), NULL, @floor
                FROM #scope s
                OUTER APPLY (
                    SELECT Total = SUM(CASE WHEN ' + @where + N' THEN ISNULL(r.'
                         + QUOTENAME(ISNULL(@measureCol, N'Days')) + N', 0) ELSE 0 END),
                           RowsSeen = COUNT(*)
                    FROM ' + @obj + N' r
                    WHERE r.PersonnelNo = s.PersonnelNo'
                    + CASE WHEN @itemCol IS NOT NULL
                           THEN N' AND (r.' + QUOTENAME(@itemCol) + N' = @code OR r.'
                                + QUOTENAME(@itemCol) + N' IS NULL)'
                           ELSE N'' END + N'
                ) x
                WHERE x.RowsSeen > 0;';

                EXEC sp_executesql @sql,
                     N'@code nvarchar(60), @floor decimal(18,4)',
                     @code = @code, @floor = @floor;
            END
            ELSE IF @evalMode = N'FLAG'
            BEGIN
                /* Met when ANY candidate row passes its own rule.  The score is carried
                   out so "why" can read "99 against 75" rather than only "not met".    */
                SET @sql = N'
                INSERT #code_hit (PersonnelNo, ViaCode, Passed, HasRow, NumValue, TextValue, Target)
                SELECT r.PersonnelNo, @code,
                       MAX(CASE WHEN ' + @where + N' THEN 1 ELSE 0 END),
                       1,
                       MAX(r.Score),
                       MAX(CAST(r.Status AS nvarchar(200))),
                       MAX(r.MaxScore)
                FROM ' + @obj + N' r
                JOIN #scope s ON s.PersonnelNo = r.PersonnelNo
                WHERE r.' + QUOTENAME(ISNULL(@itemCol, N'ItemCode')) + N' = @code'
                + CASE WHEN @kind IS NOT NULL THEN N' AND r.KindCode = @kind' ELSE N'' END + N'
                GROUP BY r.PersonnelNo;';

                EXEC sp_executesql @sql,
                     N'@code nvarchar(60), @kind nvarchar(30)',
                     @code = @code, @kind = @kind;
            END;
        END;

        FETCH NEXT FROM codeCur INTO @code, @isMain;
    END;

    CLOSE codeCur; DEALLOCATE codeCur;

    /* --- fold the candidate codes into one answer per person ---------------------- */
    DECLARE @mainEvId int, @mainMode nvarchar(20), @mainFloor decimal(18,4), @mainMapped bit;
    SELECT TOP (1) @mainEvId = e.DevEventId, @mainFloor = e.SumFloor,
           @mainMode = k.EvalModeCode,
           @mainMapped = ISNULL(s.IsMapped, 0)
    FROM sel.DevEvent e
    JOIN sel.RequirementKind k ON k.KindCode = e.KindCode
    LEFT JOIN sel.EvidenceSource s ON s.KindCode = e.KindCode
    WHERE e.ItemCode = @ItemCode AND e.IsActive = 1
    ORDER BY e.DevEventId;

    INSERT #met (PersonnelNo, ItemCode, Met, Why, NumValue, Target, ViaCode)
    SELECT sc.PersonnelNo,
           @ItemCode,
           Met = CONVERT(bit, CASE WHEN ISNULL(agg.AnyPassed, 0) = 1 THEN 1 ELSE 0 END),
           /* why is not optional: the reason, not the verdict. */
           Why =
               CASE
                   WHEN ISNULL(@mainMapped, 0) = 0
                        THEN cfg.fn_Message(N'SOURCE_UNMAPPED')
                   WHEN ISNULL(agg.AnyPassed, 0) = 1 AND @mainMode = N'SUM'
                        THEN CONVERT(nvarchar(40), CAST(ISNULL(agg.BestNum, 0) AS decimal(18,1)))
                           + N' against ' + CONVERT(nvarchar(40), CAST(ISNULL(agg.Target, 0) AS decimal(18,1)))
                   WHEN ISNULL(agg.AnyPassed, 0) = 1 AND agg.BestNum IS NOT NULL AND agg.Target IS NOT NULL
                        THEN CONVERT(nvarchar(40), CAST(agg.BestNum AS decimal(18,0)))
                           + N' against ' + CONVERT(nvarchar(40), CAST(agg.Target AS decimal(18,0)))
                           + CASE WHEN agg.PassedVia <> @ItemCode THEN N' via ' + agg.PassedVia ELSE N'' END
                   WHEN ISNULL(agg.AnyPassed, 0) = 1
                        THEN cfg.fn_Message(N'WHY_MET')
                           + CASE WHEN agg.PassedVia <> @ItemCode THEN N' via ' + agg.PassedVia ELSE N'' END
                   WHEN @mainMode = N'SUM' AND ISNULL(agg.AnyRow, 0) = 1
                        THEN CONVERT(nvarchar(40), CAST(ISNULL(agg.BestNum, 0) AS decimal(18,1)))
                           + N' against ' + CONVERT(nvarchar(40), CAST(ISNULL(@mainFloor, 0) AS decimal(18,1)))
                   WHEN ISNULL(agg.AnyRow, 0) = 0
                        THEN cfg.fn_Message(N'WHY_NOT_TAKEN')
                   WHEN agg.AnyStarted = 1
                        THEN cfg.fn_Message(N'WHY_STARTED')
                   ELSE cfg.fn_Message(N'WHY_NO_ROW_MATCHED')
               END,
           NumValue = agg.BestNum,
           Target   = CASE WHEN @mainMode = N'SUM' THEN @mainFloor ELSE agg.Target END,
           ViaCode  = agg.PassedVia
    FROM #scope sc
    OUTER APPLY
    (
        SELECT AnyPassed = MAX(CAST(h.Passed AS int)),
               AnyRow    = MAX(CAST(h.HasRow AS int)),
               BestNum   = MAX(h.NumValue),
               Target    = MAX(h.Target),
               PassedVia = MAX(CASE WHEN h.Passed = 1 THEN h.ViaCode END),
               /* A row that exists with a status but did not pass reads as started. */
               AnyStarted = MAX(CASE WHEN h.Passed = 0 AND h.TextValue IS NOT NULL THEN 1 ELSE 0 END)
        FROM #code_hit h WHERE h.PersonnelNo = sc.PersonnelNo
    ) agg;

    DROP TABLE #code_hit;
END
GO
PRINT '  sel.usp_Item_ResolveMet_Into      applied';
GO

/* sel.usp_Item_ResolveMet — the public form: one item, who in the pool meets it.
   Every read joins sec.fn_UserOrgScope, including this one.                            */
CREATE OR ALTER PROCEDURE sel.usp_Item_ResolveMet
    @LoginName   nvarchar(128),
    @ItemCode    nvarchar(60),
    @CycleId     int = NULL,
    @PersonnelNo nvarchar(30) = NULL,
    @AsOf        date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    CREATE TABLE #met
    (
        PersonnelNo nvarchar(30)  NOT NULL,
        ItemCode    nvarchar(60)  NOT NULL,
        Met         bit           NOT NULL,
        Why         nvarchar(600) NULL,
        NumValue    decimal(18,4) NULL,
        Target      decimal(18,4) NULL,
        ViaCode     nvarchar(60)  NULL
    );

    IF @PersonnelNo IS NOT NULL
        INSERT #scope (PersonnelNo)
        SELECT e.PersonnelNo FROM sel.Employee e
        JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = e.OrgCode
        WHERE e.PersonnelNo = @PersonnelNo;
    ELSE
        INSERT #scope (PersonnelNo)
        SELECT c.PersonnelNo FROM sel.CycleCandidate c
        JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = c.OrgCode
        WHERE c.CycleId = @CycleId;

    EXEC sel.usp_Item_ResolveMet_Into @ItemCode = @ItemCode, @AsOf = @AsOf;

    SELECT m.PersonnelNo, m.ItemCode, m.Met, m.Why, m.NumValue, m.Target, m.ViaCode,
           e.FullName, e.OrgCode, e.JobTitle, e.GradeCode
    FROM #met m
    JOIN sel.Employee e ON e.PersonnelNo = m.PersonnelNo
    ORDER BY m.Met DESC, e.FullName;

    DROP TABLE #met; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Item_ResolveMet           applied';
GO

/* sel.usp_Item_MetDetail — the drilldown behind every count.  It returns exactly the
   rows that count counted, including the organisation scope join, because a drilldown
   that shows a different set is the defect this rule exists to prevent.                */
CREATE OR ALTER PROCEDURE sel.usp_Item_MetDetail
    @LoginName nvarchar(128),
    @CycleId   int,
    @ItemCode  nvarchar(60),
    @MetOnly   bit = 1,
    @AsOf      date = NULL,
    @PageNo    int = 1,
    @PageSize  int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);
    IF @PageSize IS NULL SET @PageSize = CAST(ISNULL(cfg.fn_SettingNum(N'PAGE_SIZE_DEFAULT'), 50) AS int);
    IF @PageNo IS NULL OR @PageNo < 1 SET @PageNo = 1;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    CREATE TABLE #met
    (
        PersonnelNo nvarchar(30)  NOT NULL,
        ItemCode    nvarchar(60)  NOT NULL,
        Met         bit           NOT NULL,
        Why         nvarchar(600) NULL,
        NumValue    decimal(18,4) NULL,
        Target      decimal(18,4) NULL,
        ViaCode     nvarchar(60)  NULL
    );

    INSERT #scope (PersonnelNo)
    SELECT c.PersonnelNo FROM sel.CycleCandidate c
    JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = c.OrgCode
    WHERE c.CycleId = @CycleId;

    EXEC sel.usp_Item_ResolveMet_Into @ItemCode = @ItemCode, @AsOf = @AsOf;

    SELECT m.PersonnelNo, e.FullName, e.OrgCode, o.Name AS OrgName, e.JobTitle,
           e.GradeCode, m.Met, m.Why, m.NumValue, m.Target, m.ViaCode
    FROM #met m
    JOIN sel.Employee e ON e.PersonnelNo = m.PersonnelNo
    LEFT JOIN sel.OrgNode o ON o.OrgCode = e.OrgCode
    WHERE (@MetOnly = 0 OR m.Met = 1)
    ORDER BY e.FullName
    OFFSET (@PageNo - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT TotalRows = COUNT(*), MetCount = SUM(CAST(Met AS int)), PoolCount = (SELECT COUNT(*) FROM #scope)
    FROM #met WHERE (@MetOnly = 0 OR Met = 1);

    DROP TABLE #met; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Item_MetDetail            applied';
GO

/* =====================================================================================
   sel.usp_Framework_Attainment — the coverage panel
   -------------------------------------------------------------------------------------
   Pool-wide attainment: per item, how many met it; plus how many met everything, how many
   clear every mandatory item, and the median attainment.

   Above cfg.Setting 'ATTAINMENT_SAMPLE_CAP' the figures come off an evenly spaced sample
   and are scaled back, and the result says so.  An honest estimate beats a silent one and
   beats a five-second wait.
   ===================================================================================== */
CREATE OR ALTER PROCEDURE sel.usp_Framework_Attainment
    @LoginName      nvarchar(128),
    @CycleId        int,
    @DevFrameworkId int = NULL,
    @LevelNo        int = NULL,
    @AsOf           date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cap int = CAST(ISNULL(cfg.fn_SettingNum(N'ATTAINMENT_SAMPLE_CAP'), 600) AS int);

    /* The pool, inside this viewer's organisation scope. */
    CREATE TABLE #pool (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY, rn int NOT NULL);
    INSERT #pool (PersonnelNo, rn)
    SELECT c.PersonnelNo, ROW_NUMBER() OVER (ORDER BY c.PersonnelNo)
    FROM sel.CycleCandidate c
    JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = c.OrgCode
    WHERE c.CycleId = @CycleId;

    DECLARE @poolCount int = (SELECT COUNT(*) FROM #pool);
    DECLARE @isSampled bit = CASE WHEN @poolCount > @cap THEN 1 ELSE 0 END;
    DECLARE @sampleCount int = CASE WHEN @isSampled = 1 THEN @cap ELSE @poolCount END;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    IF @isSampled = 1
        /* Evenly spaced, not the first N: the first N by personnel number is an
           organisation, not a sample. */
        INSERT #scope (PersonnelNo)
        SELECT PersonnelNo FROM #pool
        WHERE (rn - 1) % (CASE WHEN @cap = 0 THEN 1 ELSE (@poolCount / @cap) END) = 0
          AND rn <= (@poolCount / (CASE WHEN @cap = 0 THEN 1 ELSE (@poolCount / @cap) END)) * (CASE WHEN @cap = 0 THEN 1 ELSE (@poolCount / @cap) END);
    ELSE
        INSERT #scope (PersonnelNo) SELECT PersonnelNo FROM #pool;

    SET @sampleCount = (SELECT COUNT(*) FROM #scope);

    CREATE TABLE #met
    (
        PersonnelNo nvarchar(30)  NOT NULL,
        ItemCode    nvarchar(60)  NOT NULL,
        Met         bit           NOT NULL,
        Why         nvarchar(600) NULL,
        NumValue    decimal(18,4) NULL,
        Target      decimal(18,4) NULL,
        ViaCode     nvarchar(60)  NULL
    );

    /* The requirements this cycle asks for. */
    CREATE TABLE #req
    (
        DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        Weight decimal(9,4) NOT NULL, IsMust bit NOT NULL,
        LevelNo int NOT NULL, DevFrameworkId int NOT NULL
    );

    INSERT #req (DevEventId, ItemCode, Weight, IsMust, LevelNo, DevFrameworkId)
    SELECT i.DevEventId, e.ItemCode, i.Weight, i.IsMust, i.LevelNo, i.DevFrameworkId
    FROM sel.CycleFramework cf
    JOIN sel.DevFrameworkItem i ON i.DevFrameworkId = cf.DevFrameworkId
    JOIN sel.DevEvent e ON e.DevEventId = i.DevEventId
    WHERE cf.CycleId = @CycleId
      AND (@DevFrameworkId IS NULL OR cf.DevFrameworkId = @DevFrameworkId)
      AND (@LevelNo IS NULL OR i.LevelNo = @LevelNo)
      AND e.ItemCode IS NOT NULL;

    /* One statement per item, each answering the whole sample. */
    DECLARE @item nvarchar(60);
    DECLARE itemCur CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT ItemCode FROM #req;
    OPEN itemCur; FETCH NEXT FROM itemCur INTO @item;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sel.usp_Item_ResolveMet_Into @ItemCode = @item, @AsOf = @AsOf;
        FETCH NEXT FROM itemCur INTO @item;
    END;
    CLOSE itemCur; DEALLOCATE itemCur;

    DECLARE @scale decimal(18,6) =
        CASE WHEN @sampleCount = 0 THEN 1 ELSE CAST(@poolCount AS decimal(18,6)) / @sampleCount END;

    /* 1 — per item, worst first. */
    SELECT r.DevEventId, r.ItemCode, e.EventCode, e.Name AS EventName,
           r.Weight, r.IsMust, r.LevelNo, r.DevFrameworkId,
           RuleText = sel.fn_EventRuleText(e.DevEventId),
           MetInSample = ISNULL(x.MetCount, 0),
           /* Scaled back to the pool when the figures came off a sample. */
           MetCount   = CAST(ROUND(ISNULL(x.MetCount, 0) * @scale, 0) AS int),
           PoolCount  = @poolCount,
           SampleCount = @sampleCount,
           IsSampled  = @isSampled
    FROM (SELECT DISTINCT DevEventId, ItemCode, Weight, IsMust, LevelNo, DevFrameworkId FROM #req) r
    JOIN sel.DevEvent e ON e.DevEventId = r.DevEventId
    OUTER APPLY (SELECT MetCount = SUM(CAST(m.Met AS int)) FROM #met m WHERE m.ItemCode = r.ItemCode) x
    ORDER BY ISNULL(x.MetCount, 0) ASC, e.EventCode;

    /* 2 — the headline figures. */
    ;WITH perPerson AS
    (
        SELECT s.PersonnelNo,
               WeightTotal = (SELECT SUM(Weight) FROM (SELECT DISTINCT DevEventId, Weight FROM #req) z),
               WeightMet = ISNULL((SELECT SUM(r.Weight)
                                   FROM (SELECT DISTINCT DevEventId, ItemCode, Weight FROM #req) r
                                   JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                   WHERE m.Met = 1), 0),
               MustOutstanding = ISNULL((SELECT COUNT(*)
                                   FROM (SELECT DISTINCT ItemCode FROM #req WHERE IsMust = 1) r
                                   LEFT JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                   WHERE ISNULL(m.Met, 0) = 0), 0),
               ItemsOutstanding = ISNULL((SELECT COUNT(*)
                                   FROM (SELECT DISTINCT ItemCode FROM #req) r
                                   LEFT JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                   WHERE ISNULL(m.Met, 0) = 0), 0)
        FROM #scope s
    ),
    pct AS
    (
        SELECT PersonnelNo,
               AttainmentPct = CASE WHEN ISNULL(WeightTotal, 0) = 0 THEN 0
                                    ELSE CAST(100.0 * WeightMet / WeightTotal AS decimal(9,4)) END,
               MustOutstanding, ItemsOutstanding
        FROM perPerson
    )
    SELECT PoolCount    = @poolCount,
           SampleCount  = @sampleCount,
           IsSampled    = @isSampled,
           ItemCount    = (SELECT COUNT(DISTINCT ItemCode) FROM #req),
           MustCount    = (SELECT COUNT(DISTINCT ItemCode) FROM #req WHERE IsMust = 1),
           MetEverything     = CAST(ROUND((SELECT COUNT(*) FROM pct WHERE ItemsOutstanding = 0) * @scale, 0) AS int),
           ClearAllMandatory = CAST(ROUND((SELECT COUNT(*) FROM pct WHERE MustOutstanding = 0) * @scale, 0) AS int),
           /* "Half the pool has finished 56% of this framework or more." */
           /* PERCENTILE_CONT returns a float; every other share in the application is a
              decimal, and a figure that changes type between screens is a figure that
              eventually rounds differently on one of them. */
           MedianAttainment = CONVERT(decimal(9,4),
                              (SELECT DISTINCT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY AttainmentPct)
                               OVER () FROM pct)),
           /* The panel says so, in the prototype's words. */
           SampleNote = CASE WHEN @isSampled = 1
                             THEN REPLACE(REPLACE(cfg.fn_Message(N'SAMPLED_FIGURES'),
                                  N'{sample}', CONVERT(nvarchar(20), @sampleCount)),
                                  N'{total}',  CONVERT(nvarchar(20), @poolCount))
                             ELSE NULL END;

    DROP TABLE #req; DROP TABLE #met; DROP TABLE #scope; DROP TABLE #pool;
END
GO
PRINT '  sel.usp_Framework_Attainment      applied';
GO

/* sel.usp_Attainment_PerPerson — one person's percentage against a cycle's requirements,
   and the requirement checklist behind it.  The profile ladder reads this, so the ladder
   and the attainment panel cannot disagree.                                             */
CREATE OR ALTER PROCEDURE sel.usp_Attainment_PerPerson
    @LoginName   nvarchar(128),
    @CycleId     int,
    @PersonnelNo nvarchar(30),
    @AsOf        date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope (PersonnelNo)
    SELECT e.PersonnelNo FROM sel.Employee e
    JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = e.OrgCode
    WHERE e.PersonnelNo = @PersonnelNo;

    CREATE TABLE #met
    (
        PersonnelNo nvarchar(30)  NOT NULL, ItemCode nvarchar(60) NOT NULL,
        Met bit NOT NULL, Why nvarchar(600) NULL,
        NumValue decimal(18,4) NULL, Target decimal(18,4) NULL, ViaCode nvarchar(60) NULL
    );

    CREATE TABLE #req
    (
        DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        Weight decimal(9,4) NOT NULL, IsMust bit NOT NULL,
        LevelNo int NOT NULL, DevFrameworkId int NOT NULL
    );
    INSERT #req
    SELECT i.DevEventId, e.ItemCode, i.Weight, i.IsMust, i.LevelNo, i.DevFrameworkId
    FROM sel.CycleFramework cf
    JOIN sel.DevFrameworkItem i ON i.DevFrameworkId = cf.DevFrameworkId
    JOIN sel.DevEvent e ON e.DevEventId = i.DevEventId
    WHERE cf.CycleId = @CycleId AND e.ItemCode IS NOT NULL;

    DECLARE @item nvarchar(60);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT ItemCode FROM #req;
    OPEN c; FETCH NEXT FROM c INTO @item;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sel.usp_Item_ResolveMet_Into @ItemCode = @item, @AsOf = @AsOf;
        FETCH NEXT FROM c INTO @item;
    END;
    CLOSE c; DEALLOCATE c;

    /* 1 — the requirement checklist, with the reason on every row. */
    SELECT r.DevEventId, r.ItemCode, e.EventCode, e.Name AS EventName, r.Weight, r.IsMust,
           r.LevelNo, r.DevFrameworkId, f.Name AS FrameworkName,
           Met = ISNULL(m.Met, 0), m.Why, m.NumValue, m.Target, m.ViaCode,
           RuleShort = sel.fn_EventRuleShort(e.DevEventId)
    FROM (SELECT DISTINCT DevEventId, ItemCode, Weight, IsMust, LevelNo, DevFrameworkId FROM #req) r
    JOIN sel.DevEvent e ON e.DevEventId = r.DevEventId
    JOIN sel.DevFramework f ON f.DevFrameworkId = r.DevFrameworkId
    LEFT JOIN #met m ON m.ItemCode = r.ItemCode
    ORDER BY r.LevelNo, ISNULL(m.Met, 0), e.EventCode;

    /* 2 — the person's percentage, and whether a "must" disqualifies them. */
    SELECT PersonnelNo = @PersonnelNo,
           WeightTotal = (SELECT SUM(Weight) FROM (SELECT DISTINCT DevEventId, Weight FROM #req) z),
           WeightMet   = ISNULL((SELECT SUM(r.Weight)
                                 FROM (SELECT DISTINCT DevEventId, ItemCode, Weight FROM #req) r
                                 JOIN #met m ON m.ItemCode = r.ItemCode WHERE m.Met = 1), 0),
           AttainmentPct = CASE WHEN ISNULL((SELECT SUM(Weight) FROM (SELECT DISTINCT DevEventId, Weight FROM #req) z), 0) = 0
                                THEN 0
                                ELSE CAST(100.0 * ISNULL((SELECT SUM(r.Weight)
                                        FROM (SELECT DISTINCT DevEventId, ItemCode, Weight FROM #req) r
                                        JOIN #met m ON m.ItemCode = r.ItemCode WHERE m.Met = 1), 0)
                                     / (SELECT SUM(Weight) FROM (SELECT DISTINCT DevEventId, Weight FROM #req) z)
                                     AS decimal(9,4)) END,
           MustOutstanding = (SELECT COUNT(*) FROM (SELECT DISTINCT ItemCode FROM #req WHERE IsMust = 1) r
                              LEFT JOIN #met m ON m.ItemCode = r.ItemCode WHERE ISNULL(m.Met, 0) = 0),
           ItemsOutstanding = (SELECT COUNT(*) FROM (SELECT DISTINCT ItemCode FROM #req) r
                               LEFT JOIN #met m ON m.ItemCode = r.ItemCode WHERE ISNULL(m.Met, 0) = 0),
           InScope = (SELECT COUNT(*) FROM #scope);

    /* 3 — the readiness ladder: each level, what it asks, and where the person stands.
       Readiness is the highest level whose percentage is met; a "must" not met
       disqualifies outright. */
    ;WITH att AS
    (
        SELECT AttainmentPct = CASE WHEN ISNULL((SELECT SUM(Weight) FROM (SELECT DISTINCT DevEventId, Weight FROM #req) z), 0) = 0
                                    THEN 0
                                    ELSE CAST(100.0 * ISNULL((SELECT SUM(r.Weight)
                                            FROM (SELECT DISTINCT DevEventId, ItemCode, Weight FROM #req) r
                                            JOIN #met m ON m.ItemCode = r.ItemCode WHERE m.Met = 1), 0)
                                         / (SELECT SUM(Weight) FROM (SELECT DISTINCT DevEventId, Weight FROM #req) z)
                                         AS decimal(9,4)) END,
               MustOutstanding = (SELECT COUNT(*) FROM (SELECT DISTINCT ItemCode FROM #req WHERE IsMust = 1) r
                                  LEFT JOIN #met m ON m.ItemCode = r.ItemCode WHERE ISNULL(m.Met, 0) = 0)
    )
    SELECT lv.CycleReadinessId, lv.LevelCode, lv.Name, lv.ThresholdPct, lv.SortOrder,
           a.AttainmentPct, a.MustOutstanding,
           IsHeld = CONVERT(bit, CASE WHEN a.MustOutstanding > 0 THEN 0
                         WHEN lv.ThresholdPct IS NULL THEN 0
                         WHEN a.AttainmentPct >= lv.ThresholdPct THEN 1 ELSE 0 END),
           ShortByPct = CASE WHEN lv.ThresholdPct IS NULL THEN NULL
                             WHEN a.AttainmentPct >= lv.ThresholdPct THEN NULL
                             ELSE CAST(lv.ThresholdPct - a.AttainmentPct AS decimal(9,2)) END,
           StateWord = CASE WHEN a.MustOutstanding > 0 THEN cfg.fn_Message(N'LADDER_DISQUALIFIED')
                            WHEN lv.ThresholdPct IS NULL THEN cfg.fn_Message(N'LADDER_NO_THRESHOLD')
                            WHEN a.AttainmentPct >= lv.ThresholdPct THEN cfg.fn_Message(N'LADDER_HELD')
                            ELSE REPLACE(cfg.fn_Message(N'LADDER_SHORT'), N'{pct}',
                                 CONVERT(nvarchar(20), CAST(lv.ThresholdPct - a.AttainmentPct AS decimal(9,1)))) END
    FROM sel.CycleReadiness lv CROSS JOIN att a
    WHERE lv.CycleId = @CycleId
    ORDER BY lv.SortOrder;

    DROP TABLE #req; DROP TABLE #met; DROP TABLE #scope;
END
GO
PRINT '  sel.usp_Attainment_PerPerson      applied';
GO

/* sel.usp_Readiness_Spread — where the pool falls today.  Each person is counted at the
   HIGHEST level they clear, plus how many hold no level yet.  It reads the same
   per-person percentages as the ladder, so the two always agree.                        */
CREATE OR ALTER PROCEDURE sel.usp_Readiness_Spread
    @LoginName nvarchar(128),
    @CycleId   int,
    @AsOf      date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @AsOf IS NULL SET @AsOf = CAST(SYSUTCDATETIME() AS date);

    DECLARE @cap int = CAST(ISNULL(cfg.fn_SettingNum(N'ATTAINMENT_SAMPLE_CAP'), 600) AS int);

    CREATE TABLE #pool (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY, rn int NOT NULL);
    INSERT #pool SELECT c.PersonnelNo, ROW_NUMBER() OVER (ORDER BY c.PersonnelNo)
    FROM sel.CycleCandidate c
    JOIN sec.fn_UserOrgScope(@LoginName) s ON s.OrgCode = c.OrgCode
    WHERE c.CycleId = @CycleId;

    DECLARE @poolCount int = (SELECT COUNT(*) FROM #pool);
    DECLARE @isSampled bit = CASE WHEN @poolCount > @cap THEN 1 ELSE 0 END;
    DECLARE @step int = CASE WHEN @isSampled = 1 AND @cap > 0 THEN (@poolCount / @cap) ELSE 1 END;

    CREATE TABLE #scope (PersonnelNo nvarchar(30) NOT NULL PRIMARY KEY);
    INSERT #scope SELECT PersonnelNo FROM #pool WHERE (rn - 1) % @step = 0;
    DECLARE @sampleCount int = (SELECT COUNT(*) FROM #scope);

    CREATE TABLE #met
    (
        PersonnelNo nvarchar(30) NOT NULL, ItemCode nvarchar(60) NOT NULL,
        Met bit NOT NULL, Why nvarchar(600) NULL,
        NumValue decimal(18,4) NULL, Target decimal(18,4) NULL, ViaCode nvarchar(60) NULL
    );
    CREATE TABLE #req
    (
        DevEventId int NOT NULL, ItemCode nvarchar(60) NOT NULL,
        Weight decimal(9,4) NOT NULL, IsMust bit NOT NULL
    );
    INSERT #req
    SELECT DISTINCT i.DevEventId, e.ItemCode, i.Weight, i.IsMust
    FROM sel.CycleFramework cf
    JOIN sel.DevFrameworkItem i ON i.DevFrameworkId = cf.DevFrameworkId
    JOIN sel.DevEvent e ON e.DevEventId = i.DevEventId
    WHERE cf.CycleId = @CycleId AND e.ItemCode IS NOT NULL;

    DECLARE @item nvarchar(60);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT ItemCode FROM #req;
    OPEN c; FETCH NEXT FROM c INTO @item;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sel.usp_Item_ResolveMet_Into @ItemCode = @item, @AsOf = @AsOf;
        FETCH NEXT FROM c INTO @item;
    END;
    CLOSE c; DEALLOCATE c;

    DECLARE @scale decimal(18,6) =
        CASE WHEN @sampleCount = 0 THEN 1 ELSE CAST(@poolCount AS decimal(18,6)) / @sampleCount END;
    DECLARE @wTotal decimal(18,4) = (SELECT SUM(Weight) FROM #req);

    ;WITH perPerson AS
    (
        SELECT s.PersonnelNo,
               AttainmentPct = CASE WHEN ISNULL(@wTotal, 0) = 0 THEN 0
                                    ELSE CAST(100.0 * ISNULL((SELECT SUM(r.Weight) FROM #req r
                                         JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                         WHERE m.Met = 1), 0) / @wTotal AS decimal(9,4)) END,
               MustOutstanding = (SELECT COUNT(*) FROM #req r
                                  LEFT JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                  WHERE r.IsMust = 1 AND ISNULL(m.Met, 0) = 0)
        FROM #scope s
    ),
    placed AS
    (
        SELECT p.PersonnelNo, p.AttainmentPct, p.MustOutstanding,
               /* The highest level they clear. */
               TopLevel = (SELECT TOP (1) lv.LevelCode FROM sel.CycleReadiness lv
                           WHERE lv.CycleId = @CycleId AND lv.ThresholdPct IS NOT NULL
                             AND p.MustOutstanding = 0 AND p.AttainmentPct >= lv.ThresholdPct
                           ORDER BY lv.ThresholdPct DESC)
        FROM perPerson p
    )
    SELECT lv.CycleReadinessId, lv.LevelCode, lv.Name, lv.ThresholdPct, lv.SortOrder,
           /* How many clear this cut at all... */
           ClearCutInSample = (SELECT COUNT(*) FROM placed p
                               WHERE p.MustOutstanding = 0 AND p.AttainmentPct >= lv.ThresholdPct),
           ClearCut = CAST(ROUND((SELECT COUNT(*) FROM placed p
                               WHERE p.MustOutstanding = 0 AND p.AttainmentPct >= lv.ThresholdPct) * @scale, 0) AS int),
           /* ...and how many are counted HERE, at the highest level they clear. */
           AtThisLevel = CAST(ROUND((SELECT COUNT(*) FROM placed p WHERE p.TopLevel = lv.LevelCode) * @scale, 0) AS int),
           PoolCount = @poolCount, SampleCount = @sampleCount, IsSampled = @isSampled
    FROM sel.CycleReadiness lv
    WHERE lv.CycleId = @CycleId
    ORDER BY lv.SortOrder;

    /* The people who hold no level yet, and those a "must" disqualifies. */
    ;WITH perPerson AS
    (
        SELECT s.PersonnelNo,
               AttainmentPct = CASE WHEN ISNULL(@wTotal, 0) = 0 THEN 0
                                    ELSE CAST(100.0 * ISNULL((SELECT SUM(r.Weight) FROM #req r
                                         JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                         WHERE m.Met = 1), 0) / @wTotal AS decimal(9,4)) END,
               MustOutstanding = (SELECT COUNT(*) FROM #req r
                                  LEFT JOIN #met m ON m.ItemCode = r.ItemCode AND m.PersonnelNo = s.PersonnelNo
                                  WHERE r.IsMust = 1 AND ISNULL(m.Met, 0) = 0)
        FROM #scope s
    )
    SELECT PoolCount = @poolCount, SampleCount = @sampleCount, IsSampled = @isSampled,
           NoLevelYet = CAST(ROUND((SELECT COUNT(*) FROM perPerson p
                            WHERE NOT EXISTS (SELECT 1 FROM sel.CycleReadiness lv
                                              WHERE lv.CycleId = @CycleId AND lv.ThresholdPct IS NOT NULL
                                                AND p.MustOutstanding = 0 AND p.AttainmentPct >= lv.ThresholdPct)) * @scale, 0) AS int),
           Disqualified = CAST(ROUND((SELECT COUNT(*) FROM perPerson WHERE MustOutstanding > 0) * @scale, 0) AS int),
           SampleNote = CASE WHEN @isSampled = 1
                             THEN REPLACE(REPLACE(cfg.fn_Message(N'SAMPLED_FIGURES'),
                                  N'{sample}', CONVERT(nvarchar(20), @sampleCount)),
                                  N'{total}',  CONVERT(nvarchar(20), @poolCount))
                             ELSE NULL END;

    DROP TABLE #req; DROP TABLE #met; DROP TABLE #scope; DROP TABLE #pool;
END
GO
PRINT '  sel.usp_Readiness_Spread          applied';
GO

PRINT '== 07_evaluation_engine complete =====================================';
GO
