/* =====================================================================================
   04_development_framework.sql  —  events, their completion rules, and frameworks
   -------------------------------------------------------------------------------------
   A development event is a thing a person can do.  Its completion rule is a set of
   condition sets, each with a mode (all / any one / none must hold) and, from the second
   set, a join (and / or / except).  sel.fn_EventRuleText restates the whole rule as one
   sentence; the list column renders sel.fn_EventRuleShort.  A sentence composed in C# is
   how a list and its rule drift apart, so neither is ever built outside this file.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 04_development_framework ==========================================';
GO

/* --- sel.MixtureModel / sel.MixturePart ---------------------------------------- */
IF OBJECT_ID('sel.MixtureModel') IS NULL
BEGIN
    CREATE TABLE sel.MixtureModel
    (
        MixtureModelId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_MixtureModel PRIMARY KEY,
        ModelCode      nvarchar(40)  NOT NULL CONSTRAINT UQ_sel_MixtureModel_Code UNIQUE,
        Name           nvarchar(160) NOT NULL,
        Description    nvarchar(400) NULL,
        TolerancePct   decimal(9,4)  NOT NULL CONSTRAINT DF_sel_MixtureModel_Tol    DEFAULT (5),
        IsActive       bit           NOT NULL CONSTRAINT DF_sel_MixtureModel_Active DEFAULT (1),
        SortOrder      int           NOT NULL CONSTRAINT DF_sel_MixtureModel_Sort   DEFAULT (0)
    );
    PRINT '  sel.MixtureModel                  created';
END
ELSE PRINT '  sel.MixtureModel                  skipped';
GO

IF OBJECT_ID('sel.MixturePart') IS NULL
BEGIN
    CREATE TABLE sel.MixturePart
    (
        MixturePartId  int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_MixturePart PRIMARY KEY,
        MixtureModelId int          NOT NULL CONSTRAINT FK_sel_MixturePart_Model REFERENCES sel.MixtureModel(MixtureModelId),
        PartValueId    int          NOT NULL CONSTRAINT FK_sel_MixturePart_Value REFERENCES cfg.DomainValue(DomainValueId),
        TargetPct      decimal(9,4) NOT NULL,
        SortOrder      int          NOT NULL CONSTRAINT DF_sel_MixturePart_Sort DEFAULT (0),
        CONSTRAINT UQ_sel_MixturePart UNIQUE (MixtureModelId, PartValueId)
    );
    PRINT '  sel.MixturePart                   created';
END
ELSE PRINT '  sel.MixturePart                   skipped';
GO

/* --- sel.DevEvent ---------------------------------------------------------------
   Type, part, measure and phase are all cfg.DomainValue references: the prototype's
   "types are editable rows" is a promise the schema has to keep.                     */
IF OBJECT_ID('sel.DevEvent') IS NULL
BEGIN
    CREATE TABLE sel.DevEvent
    (
        DevEventId     int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevEvent PRIMARY KEY,
        EventCode      nvarchar(60)  NOT NULL CONSTRAINT UQ_sel_DevEvent_Code UNIQUE,
        Name           nvarchar(300) NOT NULL,
        Description    nvarchar(600) NULL,
        EventTypeValueId int         NULL CONSTRAINT FK_sel_DevEvent_Type    REFERENCES cfg.DomainValue(DomainValueId),
        PartValueId    int           NULL CONSTRAINT FK_sel_DevEvent_Part    REFERENCES cfg.DomainValue(DomainValueId),
        MeasureValueId int           NULL CONSTRAINT FK_sel_DevEvent_Measure REFERENCES cfg.DomainValue(DomainValueId),
        PhaseValueId   int           NULL CONSTRAINT FK_sel_DevEvent_Phase   REFERENCES cfg.DomainValue(DomainValueId),
        /* Which kind of evidence answers this event, and therefore how it is judged. */
        KindCode       nvarchar(30)  NOT NULL CONSTRAINT FK_sel_DevEvent_Kind REFERENCES sel.RequirementKind(KindCode),
        /* The catalogue code this event is matched on, when it names one. */
        ItemCode       nvarchar(60)  NULL,
        PassValue      nvarchar(120) NULL,
        /* Sum-mode floor: "DaysCovered summed, must reach 90". */
        SumFloor       decimal(18,4) NULL,
        ValidityMonths int           NULL,
        RetiredFrom    date          NULL,
        IsActive       bit           NOT NULL CONSTRAINT DF_sel_DevEvent_Active DEFAULT (1),
        CreatedOnUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_DevEvent_On     DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_sel_DevEvent_Kind ON sel.DevEvent (KindCode, IsActive) INCLUDE (EventCode, Name, ItemCode);
    CREATE INDEX IX_sel_DevEvent_Item ON sel.DevEvent (ItemCode);
    PRINT '  sel.DevEvent                      created';
END
ELSE PRINT '  sel.DevEvent                      skipped';
GO

/* --- sel.DevEventConditionSet ---------------------------------------------------
   Set A, Set B ...  SetMode is all / any one / none must hold.  SetJoin (from the
   second set on) is and / or / except.  The mode selector is shown even when there is
   only one set: one set with "any one" is a legitimate rule.                          */
IF OBJECT_ID('sel.DevEventConditionSet') IS NULL
BEGIN
    CREATE TABLE sel.DevEventConditionSet
    (
        SetId          int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevEventConditionSet PRIMARY KEY,
        DevEventId     int           NOT NULL CONSTRAINT FK_sel_DECS_Event REFERENCES sel.DevEvent(DevEventId),
        SetLabel       nvarchar(10)  NOT NULL,
        SetModeValueId int           NOT NULL CONSTRAINT FK_sel_DECS_Mode REFERENCES cfg.DomainValue(DomainValueId),
        SetJoinValueId int           NULL     CONSTRAINT FK_sel_DECS_Join REFERENCES cfg.DomainValue(DomainValueId),
        SortOrder      int           NOT NULL CONSTRAINT DF_sel_DECS_Sort DEFAULT (0),
        CONSTRAINT UQ_sel_DECS UNIQUE (DevEventId, SetLabel)
    );
    PRINT '  sel.DevEventConditionSet          created';
END
ELSE PRINT '  sel.DevEventConditionSet          skipped';
GO

/* --- sel.DevEventCondition ------------------------------------------------------
   A field, an operator, and as many values as that operator's Arity requires.        */
IF OBJECT_ID('sel.DevEventCondition') IS NULL
BEGIN
    CREATE TABLE sel.DevEventCondition
    (
        ConditionId  int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevEventCondition PRIMARY KEY,
        SetId        int           NOT NULL CONSTRAINT FK_sel_DEC_Set REFERENCES sel.DevEventConditionSet(SetId),
        FieldName    nvarchar(128) NULL,          -- NULL = not chosen yet; fails its own condition only
        OperatorCode nvarchar(30)  NULL CONSTRAINT FK_sel_DEC_Op REFERENCES cfg.Operator(OperatorCode),
        Value1       nvarchar(400) NULL,
        Value2       nvarchar(400) NULL,
        SortOrder    int           NOT NULL CONSTRAINT DF_sel_DEC_Sort DEFAULT (0)
    );
    CREATE INDEX IX_sel_DEC_Set ON sel.DevEventCondition (SetId, SortOrder);
    PRINT '  sel.DevEventCondition             created';
END
ELSE PRINT '  sel.DevEventCondition             skipped';
GO

/* --- sel.DevEquivalence ---------------------------------------------------------
   An equivalent may live in a different table with different columns.  The engine
   loads each equivalent's own event, own rule and own mapped source — judging it by
   the main item's rule reads the wrong field and returns a wrong answer with no error. */
IF OBJECT_ID('sel.DevEquivalence') IS NULL
BEGIN
    CREATE TABLE sel.DevEquivalence
    (
        DevEquivalenceId int          IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevEquivalence PRIMARY KEY,
        MainItemCode     nvarchar(60) NOT NULL,
        EquivalentItemCode nvarchar(60) NOT NULL,
        Note             nvarchar(400) NULL,
        CreatedOnUtc     datetime2(3) NOT NULL CONSTRAINT DF_sel_DevEquivalence_On DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_sel_DevEquivalence UNIQUE (MainItemCode, EquivalentItemCode),
        CONSTRAINT CK_sel_DevEquivalence_NotSelf CHECK (MainItemCode <> EquivalentItemCode)
    );
    CREATE INDEX IX_sel_DevEquivalence_Equiv ON sel.DevEquivalence (EquivalentItemCode);
    PRINT '  sel.DevEquivalence                created';
END
ELSE PRINT '  sel.DevEquivalence                skipped';
GO

/* --- sel.DevFramework / sel.DevFrameworkItem ------------------------------------
   Levels are optional and renameable.  The same event may sit in several levels, so
   the key includes LevelNo.                                                           */
IF OBJECT_ID('sel.DevFramework') IS NULL
BEGIN
    CREATE TABLE sel.DevFramework
    (
        DevFrameworkId int           IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevFramework PRIMARY KEY,
        FrameworkCode  nvarchar(60)  NOT NULL CONSTRAINT UQ_sel_DevFramework_Code UNIQUE,
        Name           nvarchar(300) NOT NULL,
        Description    nvarchar(600) NULL,
        StatusValueId  int           NOT NULL CONSTRAINT FK_sel_DevFramework_Status REFERENCES cfg.DomainValue(DomainValueId),
        VersionNo      int           NOT NULL CONSTRAINT DF_sel_DevFramework_Ver    DEFAULT (1),
        UsesLevels     bit           NOT NULL CONSTRAINT DF_sel_DevFramework_Levels DEFAULT (0),
        MixtureModelId int           NULL CONSTRAINT FK_sel_DevFramework_Model REFERENCES sel.MixtureModel(MixtureModelId),
        IsActive       bit           NOT NULL CONSTRAINT DF_sel_DevFramework_Active DEFAULT (1),
        RetiredOn      date          NULL,
        CreatedOnUtc   datetime2(3)  NOT NULL CONSTRAINT DF_sel_DevFramework_On     DEFAULT (SYSUTCDATETIME())
    );
    PRINT '  sel.DevFramework                  created';
END
ELSE PRINT '  sel.DevFramework                  skipped';
GO

IF OBJECT_ID('sel.DevFrameworkItem') IS NULL
BEGIN
    CREATE TABLE sel.DevFrameworkItem
    (
        DevFrameworkItemId int         IDENTITY(1,1) NOT NULL CONSTRAINT PK_sel_DevFrameworkItem PRIMARY KEY,
        DevFrameworkId int             NOT NULL CONSTRAINT FK_sel_DFI_Framework REFERENCES sel.DevFramework(DevFrameworkId),
        LevelNo        int             NOT NULL CONSTRAINT DF_sel_DFI_Level DEFAULT (1),
        LevelName      nvarchar(120)   NULL,
        DevEventId     int             NOT NULL CONSTRAINT FK_sel_DFI_Event REFERENCES sel.DevEvent(DevEventId),
        Weight         decimal(9,4)    NOT NULL CONSTRAINT DF_sel_DFI_Weight DEFAULT (0),
        /* A "must" requirement not met disqualifies outright. */
        IsMust         bit             NOT NULL CONSTRAINT DF_sel_DFI_Must   DEFAULT (0),
        SortOrder      int             NOT NULL CONSTRAINT DF_sel_DFI_Sort   DEFAULT (0),
        CONSTRAINT UQ_sel_DFI UNIQUE (DevFrameworkId, LevelNo, DevEventId)
    );
    CREATE INDEX IX_sel_DFI_Framework ON sel.DevFrameworkItem (DevFrameworkId, LevelNo, SortOrder)
        INCLUDE (DevEventId, Weight, IsMust);
    PRINT '  sel.DevFrameworkItem              created';
END
ELSE PRINT '  sel.DevFrameworkItem              skipped';
GO

/* =====================================================================================
   The rule, restated as words.  One implementation, three shapes.
   ===================================================================================== */

/* sel.fn_ConditionText — one condition as a phrase: "Status equals Completed". */
CREATE OR ALTER FUNCTION sel.fn_ConditionText (@ConditionId int)
RETURNS nvarchar(600)
AS
BEGIN
    DECLARE @t nvarchar(600);

    SELECT @t =
        CASE
            WHEN c.FieldName IS NULL OR LTRIM(RTRIM(c.FieldName)) = N''
                THEN N'(no field chosen)'
            WHEN c.OperatorCode IS NULL
                THEN c.FieldName + N' (no comparison chosen)'
            WHEN o.Arity = 0 THEN c.FieldName + N' ' + o.Name
            WHEN o.Arity = 1 THEN c.FieldName + N' ' + o.Name + N' ' + ISNULL(c.Value1, N'(no value)')
            WHEN o.Arity = 2 THEN c.FieldName + N' ' + o.Name + N' ' + ISNULL(c.Value1, N'(no value)')
                                  + N' and ' + ISNULL(c.Value2, N'(no value)')
            ELSE c.FieldName + N' ' + o.Name + N' ' + ISNULL(c.Value1, N'(no value)')
        END
    FROM sel.DevEventCondition c
    LEFT JOIN cfg.Operator o ON o.OperatorCode = c.OperatorCode
    WHERE c.ConditionId = @ConditionId;

    RETURN @t;
END
GO
PRINT '  sel.fn_ConditionText              applied';
GO

/* sel.fn_EventRuleText — the whole rule as one sentence, live.
   An event with no sets follows its kind's default and says so.                     */
CREATE OR ALTER FUNCTION sel.fn_EventRuleText (@DevEventId int)
RETURNS nvarchar(max)
AS
BEGIN
    DECLARE @out nvarchar(max) = N'';
    DECLARE @kind nvarchar(30), @mode nvarchar(20), @itemCode nvarchar(60),
            @sumFloor decimal(18,4), @setCount int, @defaultText nvarchar(600),
            @appTable nvarchar(300), @itemColumn nvarchar(128), @measureCol nvarchar(128);

    SELECT @kind = e.KindCode, @itemCode = e.ItemCode, @sumFloor = e.SumFloor
    FROM sel.DevEvent e WHERE e.DevEventId = @DevEventId;

    IF @kind IS NULL RETURN NULL;

    SELECT @mode = k.EvalModeCode, @defaultText = k.DefaultRuleText
    FROM sel.RequirementKind k WHERE k.KindCode = @kind;

    SELECT @appTable = s.AppSchema + N'.' + s.AppTable,
           @itemColumn = ISNULL(s.ItemColumn, N'ItemCode'),
           @measureCol = s.MeasureColumn
    FROM sel.EvidenceSource s WHERE s.KindCode = @kind;

    SELECT @setCount = COUNT(*) FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId;

    /* The match, stated not configured. */
    IF @mode = N'SUM'
        SET @out = N'Read from ' + ISNULL(@appTable, N'(no table mapped)') + N' for this person. '
                 + N'The conditions below decide which rows count.';
    ELSE
        SET @out = N'Matched where ' + ISNULL(@appTable, N'(no table mapped)') + N'.' + @itemColumn
                 + N' = ' + ISNULL(@itemCode, N'(no item code)') + N'.';

    IF @setCount = 0
    BEGIN
        SET @out = @out + N' No conditions are set, so this event follows the default for its kind: '
                 + ISNULL(@defaultText, N'(no default recorded)');
        IF @mode = N'SUM' AND @sumFloor IS NOT NULL
            SET @out = @out + N' ' + ISNULL(@measureCol, N'The measure') + N' summed, must reach '
                     + CONVERT(nvarchar(40), CAST(@sumFloor AS decimal(18,2))) + N'.';
        RETURN @out;
    END;

    /* Each set, folded left to right with its join. */
    DECLARE @setText nvarchar(max) = N'';
    SELECT @setText = @setText
        + CASE WHEN cs.SortOrder = (SELECT MIN(SortOrder) FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId)
               THEN N' '
               ELSE N' ' + ISNULL(jv.Name, N'and') + N' ' END
        + N'Set ' + cs.SetLabel + N': ' + mv.Name + N' of ['
        + STUFF((SELECT N'; ' + sel.fn_ConditionText(c.ConditionId)
                 FROM sel.DevEventCondition c
                 WHERE c.SetId = cs.SetId
                 ORDER BY c.SortOrder, c.ConditionId
                 FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, N'')
        + N']'
    FROM sel.DevEventConditionSet cs
    JOIN cfg.DomainValue mv ON mv.DomainValueId = cs.SetModeValueId
    LEFT JOIN cfg.DomainValue jv ON jv.DomainValueId = cs.SetJoinValueId
    WHERE cs.DevEventId = @DevEventId
    ORDER BY cs.SortOrder, cs.SetLabel;

    SET @out = @out + ISNULL(@setText, N'');

    IF @mode = N'SUM' AND @sumFloor IS NOT NULL
        SET @out = @out + N' ' + ISNULL(@measureCol, N'The measure') + N' summed, must reach '
                 + CONVERT(nvarchar(40), CAST(@sumFloor AS decimal(18,2))) + N'.';

    RETURN @out;
END
GO
PRINT '  sel.fn_EventRuleText              applied';
GO

/* sel.fn_EventRuleShort — what the events list renders in its rule column. */
CREATE OR ALTER FUNCTION sel.fn_EventRuleShort (@DevEventId int)
RETURNS nvarchar(400)
AS
BEGIN
    DECLARE @kind nvarchar(30), @mode nvarchar(20), @sumFloor decimal(18,4),
            @setCount int, @condCount int, @measureCol nvarchar(128), @passValue nvarchar(120);

    SELECT @kind = e.KindCode, @sumFloor = e.SumFloor, @passValue = e.PassValue
    FROM sel.DevEvent e WHERE e.DevEventId = @DevEventId;
    IF @kind IS NULL RETURN NULL;

    SELECT @mode = EvalModeCode FROM sel.RequirementKind WHERE KindCode = @kind;
    SELECT @measureCol = MeasureColumn FROM sel.EvidenceSource WHERE KindCode = @kind;

    SELECT @setCount = COUNT(*) FROM sel.DevEventConditionSet WHERE DevEventId = @DevEventId;
    SELECT @condCount = COUNT(*) FROM sel.DevEventCondition c
    JOIN sel.DevEventConditionSet cs ON cs.SetId = c.SetId WHERE cs.DevEventId = @DevEventId;

    IF @mode = N'SUM'
        RETURN ISNULL(@measureCol, N'Measure') + N' summed, must reach '
             + ISNULL(CONVERT(nvarchar(40), CAST(@sumFloor AS decimal(18,2))), N'(no floor)')
             + CASE WHEN @setCount > 0 THEN N' · ' + CONVERT(nvarchar(10), @condCount) + N' condition'
                                             + CASE WHEN @condCount = 1 THEN N'' ELSE N's' END
                    ELSE N' · kind default' END;

    IF @setCount = 0
        RETURN N'Kind default' + CASE WHEN @passValue IS NOT NULL THEN N' · passes at ' + @passValue ELSE N'' END;

    RETURN CONVERT(nvarchar(10), @setCount) + N' set' + CASE WHEN @setCount = 1 THEN N'' ELSE N's' END
         + N' · ' + CONVERT(nvarchar(10), @condCount) + N' condition'
         + CASE WHEN @condCount = 1 THEN N'' ELSE N's' END;
END
GO
PRINT '  sel.fn_EventRuleShort             applied';
GO

/* sel.fn_ItemCandidateCodes — an item plus every code equivalent to it.
   Step 1 of the evaluation engine, used by everything that judges a requirement.     */
CREATE OR ALTER FUNCTION sel.fn_ItemCandidateCodes (@ItemCode nvarchar(60))
RETURNS TABLE
AS
RETURN
    SELECT ItemCode = @ItemCode, IsMain = CAST(1 AS bit)
    UNION
    SELECT EquivalentItemCode, CAST(0 AS bit) FROM sel.DevEquivalence WHERE MainItemCode = @ItemCode;
GO
PRINT '  sel.fn_ItemCandidateCodes         applied';
GO

/* =====================================================================================
   Read procedures for the Development framework screens
   ===================================================================================== */

CREATE OR ALTER PROCEDURE sel.usp_DevEvent_List
    @LoginName  nvarchar(128),
    @Search     nvarchar(200) = NULL,
    @PartCode   nvarchar(60)  = NULL,
    @TypeCode   nvarchar(60)  = NULL,
    @ActiveOnly bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT e.DevEventId, e.EventCode, e.Name, e.Description, e.KindCode, k.Name AS KindName,
           k.EvalModeCode, e.ItemCode, e.PassValue, e.SumFloor, e.ValidityMonths,
           e.RetiredFrom, e.IsActive,
           tv.ValueCode AS EventTypeCode, tv.Name AS EventTypeName,
           pv.ValueCode AS PartCode,      pv.Name AS PartName,
           mv.ValueCode AS MeasureCode,   mv.Name AS MeasureName,
           ph.ValueCode AS PhaseCode,     ph.Name AS PhaseName,
           /* The list's rule column renders the function, never a sentence composed
              outside the database. */
           RuleShort = sel.fn_EventRuleShort(e.DevEventId),
           EquivalentCount = (SELECT COUNT(*) FROM sel.DevEquivalence q WHERE q.MainItemCode = e.ItemCode),
           FrameworkCount  = (SELECT COUNT(DISTINCT i.DevFrameworkId) FROM sel.DevFrameworkItem i WHERE i.DevEventId = e.DevEventId),
           SourceIsMapped  = ISNULL((SELECT s.IsMapped FROM sel.EvidenceSource s WHERE s.KindCode = e.KindCode), 0)
    FROM sel.DevEvent e
    JOIN sel.RequirementKind k ON k.KindCode = e.KindCode
    LEFT JOIN cfg.DomainValue tv ON tv.DomainValueId = e.EventTypeValueId
    LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = e.PartValueId
    LEFT JOIN cfg.DomainValue mv ON mv.DomainValueId = e.MeasureValueId
    LEFT JOIN cfg.DomainValue ph ON ph.DomainValueId = e.PhaseValueId
    WHERE (@Search   IS NULL OR e.EventCode LIKE N'%' + @Search + N'%' OR e.Name LIKE N'%' + @Search + N'%')
      AND (@PartCode IS NULL OR pv.ValueCode = @PartCode)
      AND (@TypeCode IS NULL OR tv.ValueCode = @TypeCode)
      AND (@ActiveOnly = 0 OR e.IsActive = 1)
    ORDER BY e.EventCode;
END
GO
PRINT '  sel.usp_DevEvent_List             applied';
GO

/* sel.usp_DevEvent_Detail — the "Where completion comes from" rule editor. */
CREATE OR ALTER PROCEDURE sel.usp_DevEvent_Detail
    @LoginName  nvarchar(128),
    @DevEventId int
AS
BEGIN
    SET NOCOUNT ON;

    /* 1 — the event, its match sentence and its whole rule restated. */
    SELECT e.DevEventId, e.EventCode, e.Name, e.Description, e.KindCode, k.Name AS KindName,
           k.EvalModeCode, k.DefaultRuleText, e.ItemCode, e.PassValue, e.SumFloor,
           e.ValidityMonths, e.RetiredFrom, e.IsActive,
           e.EventTypeValueId, e.PartValueId, e.MeasureValueId, e.PhaseValueId,
           RuleText  = sel.fn_EventRuleText(e.DevEventId),
           RuleShort = sel.fn_EventRuleShort(e.DevEventId),
           s.EvidenceSourceId, s.AppSchema, s.AppTable, s.ItemColumn, s.MeasureColumn,
           s.StatusColumn, SourceIsMapped = ISNULL(s.IsMapped, 0),
           SetCount = (SELECT COUNT(*) FROM sel.DevEventConditionSet cs WHERE cs.DevEventId = e.DevEventId),
           /* An event with no sets follows its kind's default and says so; an override
              says so and offers a one-click revert. */
           FollowsKindDefault = CASE WHEN (SELECT COUNT(*) FROM sel.DevEventConditionSet cs
                                           WHERE cs.DevEventId = e.DevEventId) = 0 THEN 1 ELSE 0 END,
           UnmappedWarning = CASE WHEN ISNULL(s.IsMapped, 0) = 0 THEN cfg.fn_Message(N'SOURCE_UNMAPPED') ELSE NULL END
    FROM sel.DevEvent e
    JOIN sel.RequirementKind k ON k.KindCode = e.KindCode
    LEFT JOIN sel.EvidenceSource s ON s.KindCode = e.KindCode
    WHERE e.DevEventId = @DevEventId;

    /* 2 — the condition sets. */
    SELECT cs.SetId, cs.DevEventId, cs.SetLabel, cs.SortOrder,
           cs.SetModeValueId, mv.ValueCode AS SetModeCode, mv.Name AS SetModeName,
           cs.SetJoinValueId, jv.ValueCode AS SetJoinCode, jv.Name AS SetJoinName
    FROM sel.DevEventConditionSet cs
    JOIN cfg.DomainValue mv ON mv.DomainValueId = cs.SetModeValueId
    LEFT JOIN cfg.DomainValue jv ON jv.DomainValueId = cs.SetJoinValueId
    WHERE cs.DevEventId = @DevEventId
    ORDER BY cs.SortOrder, cs.SetLabel;

    /* 3 — the conditions. */
    SELECT c.ConditionId, c.SetId, c.FieldName, c.OperatorCode, o.Name AS OperatorName,
           o.Arity, c.Value1, c.Value2, c.SortOrder,
           Phrase = sel.fn_ConditionText(c.ConditionId)
    FROM sel.DevEventCondition c
    JOIN sel.DevEventConditionSet cs ON cs.SetId = c.SetId
    LEFT JOIN cfg.Operator o ON o.OperatorCode = c.OperatorCode
    WHERE cs.DevEventId = @DevEventId
    ORDER BY cs.SortOrder, c.SortOrder, c.ConditionId;

    /* 4 — the fields this source offers, with the operator each one proposes.
       Never carry over an operator that reads as nonsense. */
    SELECT esc.EvidenceSourceColumnId, esc.ColumnName, esc.Caption, esc.DataType,
           esc.IsExpiryDate, esc.IsPhysical, esc.IsLearned, esc.UsageCount,
           ProposedOperator =
               CASE WHEN esc.IsExpiryDate = 1 THEN N'AFTER_TODAY'
                    WHEN esc.DataType = N'date'   THEN N'IS_RECORDED'
                    WHEN esc.DataType = N'number' THEN N'GE'
                    ELSE N'EQ' END
    FROM sel.EvidenceSourceColumn esc
    JOIN sel.EvidenceSource s ON s.EvidenceSourceId = esc.EvidenceSourceId
    JOIN sel.DevEvent e ON e.KindCode = s.KindCode
    WHERE e.DevEventId = @DevEventId
    ORDER BY esc.SortOrder, esc.ColumnName;

    /* 5 — equivalencies, managed inline. */
    SELECT q.DevEquivalenceId, q.MainItemCode, q.EquivalentItemCode, q.Note,
           EquivName = ci.Name,
           EquivKind = ci.KindCode
    FROM sel.DevEquivalence q
    LEFT JOIN sel.CatalogItem ci ON ci.ItemCode = q.EquivalentItemCode
    WHERE q.MainItemCode = (SELECT ItemCode FROM sel.DevEvent WHERE DevEventId = @DevEventId)
    ORDER BY q.EquivalentItemCode;
END
GO
PRINT '  sel.usp_DevEvent_Detail           applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Framework_List
    @LoginName  nvarchar(128),
    @Search     nvarchar(200) = NULL,
    @ActiveOnly bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.DevFrameworkId, f.FrameworkCode, f.Name, f.Description, f.VersionNo, f.UsesLevels,
           f.MixtureModelId, mm.Name AS MixtureModelName, f.IsActive, f.RetiredOn,
           f.StatusValueId, sv.ValueCode AS StatusCode, sv.Name AS StatusName, sv.SemanticRole AS StatusRole,
           EventCount = (SELECT COUNT(DISTINCT i.DevEventId) FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = f.DevFrameworkId),
           LevelCount = (SELECT COUNT(DISTINCT i.LevelNo)    FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = f.DevFrameworkId),
           CycleCount = (SELECT COUNT(*) FROM sel.CycleFramework cf WHERE cf.DevFrameworkId = f.DevFrameworkId),
           WeightTotal = (SELECT SUM(i.Weight) FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = f.DevFrameworkId)
    FROM sel.DevFramework f
    JOIN cfg.DomainValue sv ON sv.DomainValueId = f.StatusValueId
    LEFT JOIN sel.MixtureModel mm ON mm.MixtureModelId = f.MixtureModelId
    WHERE (@Search IS NULL OR f.Name LIKE N'%' + @Search + N'%' OR f.FrameworkCode LIKE N'%' + @Search + N'%')
      AND (@ActiveOnly = 0 OR (f.IsActive = 1 AND sv.ValueCode = N'ACTIVE'))
    ORDER BY f.Name;
END
GO
PRINT '  sel.usp_Framework_List            applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_Framework_Detail
    @LoginName     nvarchar(128),
    @DevFrameworkId int
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.DevFrameworkId, f.FrameworkCode, f.Name, f.Description, f.VersionNo, f.UsesLevels,
           f.MixtureModelId, mm.Name AS MixtureModelName, mm.TolerancePct,
           f.IsActive, f.RetiredOn, f.StatusValueId, sv.ValueCode AS StatusCode, sv.Name AS StatusName,
           WeightTarget = cfg.fn_SettingNum(N'WEIGHT_TOTAL_TARGET'),
           WeightTotal  = (SELECT SUM(i.Weight) FROM sel.DevFrameworkItem i WHERE i.DevFrameworkId = f.DevFrameworkId)
    FROM sel.DevFramework f
    JOIN cfg.DomainValue sv ON sv.DomainValueId = f.StatusValueId
    LEFT JOIN sel.MixtureModel mm ON mm.MixtureModelId = f.MixtureModelId
    WHERE f.DevFrameworkId = @DevFrameworkId;

    /* Requirement rows, grouped by level, with each one's rule as a phrase. */
    SELECT i.DevFrameworkItemId, i.DevFrameworkId, i.LevelNo, i.LevelName, i.DevEventId,
           i.Weight, i.IsMust, i.SortOrder,
           e.EventCode, e.Name AS EventName, e.KindCode, e.ItemCode,
           pv.ValueCode AS PartCode, pv.Name AS PartName,
           RuleShort = sel.fn_EventRuleShort(e.DevEventId),
           /* Warnings: a missing event, a zero weight, an empty level. */
           WarnZeroWeight = CONVERT(bit, CASE WHEN i.Weight = 0 THEN 1 ELSE 0 END),
           WarnInactive   = CONVERT(bit, CASE WHEN e.IsActive = 0 THEN 1 ELSE 0 END)
    FROM sel.DevFrameworkItem i
    JOIN sel.DevEvent e ON e.DevEventId = i.DevEventId
    LEFT JOIN cfg.DomainValue pv ON pv.DomainValueId = e.PartValueId
    WHERE i.DevFrameworkId = @DevFrameworkId
    ORDER BY i.LevelNo, i.SortOrder, e.EventCode;

    /* The mixture: weight actually placed per part, against the model's target. */
    SELECT PartValueId = pv.DomainValueId, PartCode = pv.ValueCode, PartName = pv.Name,
           TargetPct = mp.TargetPct,
           ActualWeight = ISNULL(w.W, 0),
           ActualPct = CASE WHEN ISNULL(tw.TotalW, 0) = 0 THEN 0
                            ELSE CAST(100.0 * ISNULL(w.W, 0) / tw.TotalW AS decimal(9,4)) END,
           Tolerance = mm.TolerancePct
    FROM sel.DevFramework f
    JOIN sel.MixtureModel mm ON mm.MixtureModelId = f.MixtureModelId
    JOIN sel.MixturePart mp ON mp.MixtureModelId = mm.MixtureModelId
    JOIN cfg.DomainValue pv ON pv.DomainValueId = mp.PartValueId
    OUTER APPLY (SELECT W = SUM(i.Weight) FROM sel.DevFrameworkItem i
                 JOIN sel.DevEvent e ON e.DevEventId = i.DevEventId
                 WHERE i.DevFrameworkId = f.DevFrameworkId AND e.PartValueId = pv.DomainValueId) w
    OUTER APPLY (SELECT TotalW = SUM(i.Weight) FROM sel.DevFrameworkItem i
                 WHERE i.DevFrameworkId = f.DevFrameworkId) tw
    WHERE f.DevFrameworkId = @DevFrameworkId
    ORDER BY mp.SortOrder;
END
GO
PRINT '  sel.usp_Framework_Detail          applied';
GO

CREATE OR ALTER PROCEDURE sel.usp_MixtureModel_List
    @LoginName nvarchar(128)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT m.MixtureModelId, m.ModelCode, m.Name, m.Description, m.TolerancePct, m.IsActive, m.SortOrder,
           PartTotal = (SELECT SUM(p.TargetPct) FROM sel.MixturePart p WHERE p.MixtureModelId = m.MixtureModelId),
           UsedBy    = (SELECT COUNT(*) FROM sel.DevFramework f WHERE f.MixtureModelId = m.MixtureModelId)
    FROM sel.MixtureModel m ORDER BY m.SortOrder, m.Name;

    SELECT p.MixturePartId, p.MixtureModelId, p.PartValueId, dv.ValueCode AS PartCode,
           dv.Name AS PartName, p.TargetPct, p.SortOrder
    FROM sel.MixturePart p
    JOIN cfg.DomainValue dv ON dv.DomainValueId = p.PartValueId
    ORDER BY p.MixtureModelId, p.SortOrder;
END
GO
PRINT '  sel.usp_MixtureModel_List         applied';
GO

PRINT '== 04_development_framework complete =================================';
GO
