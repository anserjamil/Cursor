/* =====================================================================================
   09_reference_data.sql  —  the seeded configuration
   -------------------------------------------------------------------------------------
   Everything the application would otherwise hardcode.  Each block is a MERGE against a
   literal source, so running this twice changes nothing.

   SemanticRole names a meaning, never a colour: the stylesheet turns 'warning' into
   whatever amber is this year.  The database never carries a hex code.
   ===================================================================================== */
SET NOCOUNT ON;
GO

PRINT '';
PRINT '== 09_reference_data =================================================';
GO

/* ---------------------------------------------------------------------------------
   Domains
   --------------------------------------------------------------------------------- */
MERGE cfg.Domain AS t
USING (VALUES
    (N'CYCLE_STATUS',     N'Cycle status',            N'Where a cycle is in its life.', 1, 10),
    (N'SET_MODE',         N'Condition set mode',      N'How the conditions inside one set combine.', 1, 20),
    (N'SET_JOIN',         N'Condition set join',      N'How a condition set joins the ones before it.', 1, 30),
    (N'CRITERIA_JOIN',    N'Criterion set join',      N'How a criterion set joins the ones before it.', 1, 40),
    (N'DECISION',         N'Decision',                N'Every decision word the log can carry.', 1, 50),
    (N'MANAGEMENT_LEVEL', N'Management level',        N'Who can perform a stage.', 0, 60),
    (N'FRAMEWORK_STATUS', N'Framework status',        N'Draft or active.', 1, 70),
    (N'EVENT_TYPE',       N'Event type',              N'What kind of thing a development event is.', 0, 80),
    (N'PART',             N'Mixture part',            N'Experience, assessment or course.', 0, 90),
    (N'MEASURE',          N'Measure',                 N'How an event is measured.', 0, 100),
    (N'PHASE',            N'Phase',                   N'Before, after, or neither.', 0, 110),
    (N'CANDIDATE_SOURCE', N'Candidate source',        N'How a person came to be in the pool.', 1, 120),
    (N'COVERAGE_TYPE',    N'Coverage type',           N'Acting, secondment or project cover.', 0, 130),
    (N'ITEM_CATEGORY',    N'Item category',           N'How the catalogue is grouped.', 0, 140),
    (N'IDP_STATUS',       N'Plan item status',        N'Where one requirement is in a plan.', 1, 150),
    (N'IDP_SOURCE',       N'Plan item source',        N'What put this requirement in the plan.', 1, 160),
    (N'RATING_BAND',      N'Performance rating band', N'The letters a performance year is reported as.', 0, 170),
    (N'JOB_SUFFIX_ROLE',  N'Job suffix role',         N'Incumbent or successor.', 1, 180)
) AS s (DomainCode, Name, Description, IsSystem, SortOrder)
   ON t.DomainCode = s.DomainCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             IsSystem = s.IsSystem, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (DomainCode, Name, Description, IsSystem, SortOrder)
    VALUES (s.DomainCode, s.Name, s.Description, s.IsSystem, s.SortOrder);
PRINT '  cfg.Domain                        seeded';
GO

/* ---------------------------------------------------------------------------------
   Domain values
   --------------------------------------------------------------------------------- */
DECLARE @dv TABLE (DomainCode nvarchar(60), ValueCode nvarchar(60), Name nvarchar(160),
                   SemanticRole nvarchar(40), SortOrder int, IsSystem bit);

INSERT @dv (DomainCode, ValueCode, Name, SemanticRole, SortOrder, IsSystem) VALUES
/* Cycle status */
 (N'CYCLE_STATUS', N'DRAFT',     N'Draft',      N'neutral',  10, 1),
 (N'CYCLE_STATUS', N'ACTIVE',    N'Active',     N'positive', 20, 1),
 (N'CYCLE_STATUS', N'CLOSED',    N'Closed',     N'muted',    30, 1),
 (N'CYCLE_STATUS', N'CANCELLED', N'Cancelled',  N'danger',   40, 1),

/* How conditions inside one set combine.  One set with "any one" is a legitimate rule,
   so the mode selector is shown even when there is only one set. */
 (N'SET_MODE', N'ALL',  N'all',      NULL, 10, 1),
 (N'SET_MODE', N'ANY',  N'any one',  NULL, 20, 1),
 (N'SET_MODE', N'NONE', N'none',     NULL, 30, 1),

/* How a condition set joins the ones before it. */
 (N'SET_JOIN', N'AND',    N'and',    NULL, 10, 1),
 (N'SET_JOIN', N'OR',     N'or',     NULL, 20, 1),
 (N'SET_JOIN', N'EXCEPT', N'except', NULL, 30, 1),

/* How a criterion set joins the ones before it — the same idea, read in the
   prototype's words. */
 (N'CRITERIA_JOIN', N'UNION',     N'or also',  NULL, 10, 1),
 (N'CRITERIA_JOIN', N'INTERSECT', N'and also', NULL, 20, 1),
 (N'CRITERIA_JOIN', N'EXCEPT',    N'but not',  NULL, 30, 1),

/* Decision words.  Amber is the watch list, red is dropped, grey is undecided, and the
   outcome pill is solid ink. */
 (N'DECISION', N'NONE',            N'No decision',            N'neutral',  10, 1),
 (N'DECISION', N'NOMINATED',       N'Nominated',              N'positive', 20, 1),
 (N'DECISION', N'KEPT',            N'Kept nominated',         N'positive', 30, 1),
 (N'DECISION', N'WATCH',           N'Watch list',             N'warning',  40, 1),
 (N'DECISION', N'DROPPED',         N'Dropped',                N'danger',   50, 1),
 (N'DECISION', N'REOPENED',        N'Reopened',               N'info',     60, 1),
 (N'DECISION', N'NONHIPO',         N'Non HIPO pull',          N'info',     70, 1),
 (N'DECISION', N'SUCCESSOR',       N'Named a successor',      N'positive', 80, 1),
 (N'DECISION', N'READINESS',       N'Readiness',              N'info',     90, 1),
 (N'DECISION', N'DEVPLAN',         N'Development plan',       N'info',    100, 1),
 (N'DECISION', N'CALIBRATED',      N'Calibrated',             N'positive',110, 1),
 (N'DECISION', N'ACTIVITY',        N'Activity proposed',      N'info',    120, 1),
 (N'DECISION', N'PLAN_APPROVED',   N'Approved into the plan', N'positive',130, 1),
 (N'DECISION', N'RETURNED',        N'Returned to Identify',   N'warning', 140, 1),
 (N'DECISION', N'NOT_REQUIRED',    N'Not required',           N'muted',   150, 1),
/* The calibration grades. */
 (N'DECISION', N'VP_VERY_STRONG',  N'VP-Very Strong',         N'positive',160, 1),
 (N'DECISION', N'DIR_VERY_STRONG', N'Director-Very Strong',   N'positive',170, 1),
 (N'DECISION', N'DIR_STRONG',      N'Director-Strong',        N'positive',180, 1),
 (N'DECISION', N'MGR_STRONG',      N'Manager-Strong',         N'positive',190, 1),

/* The managed management-level list behind "Who can perform a stage". */
 (N'MANAGEMENT_LEVEL', N'PRESIDENT',  N'President',           NULL, 10, 0),
 (N'MANAGEMENT_LEVEL', N'EVP',        N'Executive VP',        NULL, 20, 0),
 (N'MANAGEMENT_LEVEL', N'SVP',        N'Senior VP',           NULL, 30, 0),
 (N'MANAGEMENT_LEVEL', N'VP',         N'Vice President',      NULL, 40, 0),
 (N'MANAGEMENT_LEVEL', N'DIRECTOR',   N'Director',            NULL, 50, 0),
 (N'MANAGEMENT_LEVEL', N'MANAGER',    N'Manager',             NULL, 60, 0),
 (N'MANAGEMENT_LEVEL', N'SUPERVISOR', N'Supervisor',          NULL, 70, 0),

 (N'FRAMEWORK_STATUS', N'DRAFT',  N'Draft',  N'neutral',  10, 1),
 (N'FRAMEWORK_STATUS', N'ACTIVE', N'Active', N'positive', 20, 1),

/* Event types are editable rows, not an enum. */
 (N'EVENT_TYPE', N'ASSIGNMENT', N'Assignment', NULL, 10, 0),
 (N'EVENT_TYPE', N'ROTATION',   N'Rotation',   NULL, 20, 0),
 (N'EVENT_TYPE', N'PROJECT',    N'Project',    NULL, 30, 0),
 (N'EVENT_TYPE', N'ASSESSMENT', N'Assessment', NULL, 40, 0),
 (N'EVENT_TYPE', N'COMPETENCY', N'Competency', NULL, 50, 0),
 (N'EVENT_TYPE', N'SURVEY',     N'Survey',     NULL, 60, 0),
 (N'EVENT_TYPE', N'COURSE',     N'Course',     NULL, 70, 0),

 (N'PART', N'EXPERIENCE', N'Experience', NULL, 10, 0),
 (N'PART', N'ASSESSMENT', N'Assessment', NULL, 20, 0),
 (N'PART', N'COURSE',     N'Course',     NULL, 30, 0),

 (N'MEASURE', N'COMPLETION', N'Completion', NULL, 10, 0),
 (N'MEASURE', N'SCORE',      N'Score',      NULL, 20, 0),
 (N'MEASURE', N'DAYS',       N'Days',       NULL, 30, 0),
 (N'MEASURE', N'MONTHS',     N'Months',     NULL, 40, 0),

 (N'PHASE', N'NONE', N'—',    NULL, 10, 0),
 (N'PHASE', N'PRE',  N'Pre',  NULL, 20, 0),
 (N'PHASE', N'POST', N'Post', NULL, 30, 0),

/* The source tag that persists through every stage. */
 (N'CANDIDATE_SOURCE', N'ELIGIBLE',         N'Eligible',         N'neutral', 10, 1),
 (N'CANDIDATE_SOURCE', N'EXISTING POOL',    N'Existing pool',    N'info',    20, 1),
 (N'CANDIDATE_SOURCE', N'OUTSIDE CRITERIA', N'Outside criteria', N'warning', 30, 1),

 (N'COVERAGE_TYPE', N'ACTING',     N'Acting',     NULL, 10, 0),
 (N'COVERAGE_TYPE', N'SECONDMENT', N'Secondment', NULL, 20, 0),
 (N'COVERAGE_TYPE', N'PROJECT',    N'Project',    NULL, 30, 0),

 (N'ITEM_CATEGORY', N'ASSESSMENT',      N'Assessment',       NULL, 10, 0),
 (N'ITEM_CATEGORY', N'FEEDBACK360',     N'360 feedback',     NULL, 20, 0),
 (N'ITEM_CATEGORY', N'DIRECTOR_COURSE', N'Director courses', NULL, 30, 0),
 (N'ITEM_CATEGORY', N'COURSE',          N'Course',           NULL, 40, 0),
 (N'ITEM_CATEGORY', N'COVERAGE_DAYS',   N'Coverage days',    NULL, 50, 0),
 (N'ITEM_CATEGORY', N'ROSTER_FIGURE',   N'Roster figure',    NULL, 60, 0),

 (N'IDP_STATUS', N'OPEN',      N'Open',      N'neutral',  10, 1),
 (N'IDP_STATUS', N'PENCILLED', N'Pencilled', N'warning',  20, 1),
 (N'IDP_STATUS', N'BOOKED',    N'Booked',    N'info',     30, 1),
 (N'IDP_STATUS', N'MET',       N'Met',       N'positive', 40, 1),

 (N'IDP_SOURCE', N'LEVEL',    N'Readiness level', NULL, 10, 1),
 (N'IDP_SOURCE', N'PLAN',     N'Succession plan', NULL, 20, 1),
 (N'IDP_SOURCE', N'POSITION', N'Position',        NULL, 30, 1),

 (N'RATING_BAND', N'A', N'A', N'positive', 10, 0),
 (N'RATING_BAND', N'B', N'B', N'positive', 20, 0),
 (N'RATING_BAND', N'C', N'C', N'neutral',  30, 0),
 (N'RATING_BAND', N'D', N'D', N'warning',  40, 0),
 (N'RATING_BAND', N'E', N'E', N'danger',   50, 0),

 (N'JOB_SUFFIX_ROLE', N'INCUMBENT', N'Incumbent', NULL, 10, 1),
 (N'JOB_SUFFIX_ROLE', N'SUCCESSOR', N'Successor', NULL, 20, 1);

MERGE cfg.DomainValue AS t
USING (SELECT d.DomainId, v.ValueCode, v.Name, v.SemanticRole, v.SortOrder, v.IsSystem
       FROM @dv v JOIN cfg.Domain d ON d.DomainCode = v.DomainCode) AS s
   ON t.DomainId = s.DomainId AND t.ValueCode = s.ValueCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, SemanticRole = s.SemanticRole,
                             SortOrder = s.SortOrder, IsSystem = s.IsSystem
WHEN NOT MATCHED BY TARGET THEN
    INSERT (DomainId, ValueCode, Name, SemanticRole, SortOrder, IsSystem)
    VALUES (s.DomainId, s.ValueCode, s.Name, s.SemanticRole, s.SortOrder, s.IsSystem);
PRINT '  cfg.DomainValue                   seeded';
GO

/* ---------------------------------------------------------------------------------
   Operators — the only place the SQL shape of a comparison is written down.
   They read in words, because every rule is shown back to the user as a sentence.
   --------------------------------------------------------------------------------- */
MERGE cfg.Operator AS t
USING (VALUES
    (N'GE',          N'is at least',     N'{col} >= {v1}',            N'number,date',           1, 10),
    (N'GT',          N'is over',         N'{col} > {v1}',             N'number,date',           1, 20),
    (N'LE',          N'is at most',      N'{col} <= {v1}',            N'number,date',           1, 30),
    (N'LT',          N'is under',        N'{col} < {v1}',             N'number,date',           1, 40),
    (N'EQ',          N'is',              N'{col} = {v1}',             N'text,number,date,bit',  1, 50),
    (N'NE',          N'is not',          N'{col} <> {v1}',            N'text,number,date,bit',  1, 60),
    (N'BETWEEN',     N'is between',      N'{col} BETWEEN {v1} AND {v2}', N'number,date',        2, 70),
    (N'IN',          N'is one of',       N'{col} IN ({list1})',       N'text,number',           1, 80),
    (N'NOTIN',       N'is none of',      N'{col} NOT IN ({list1})',   N'text,number',           1, 90),
    (N'ISNULL',      N'is not recorded', N'{col} IS NULL',            N'text,number,date,bit',  0, 100),
    (N'IS_RECORDED', N'is recorded',     N'{col} IS NOT NULL',        N'text,number,date,bit',  0, 110),
    (N'AFTER_TODAY', N'is after today',  N'{col} > {asof}',           N'date',                  0, 120),
    (N'CONTAINS',    N'contains',        N'{col} LIKE {like1}',       N'text',                  1, 130)
) AS s (OperatorCode, Name, SqlTemplate, AppliesTo, Arity, SortOrder)
   ON t.OperatorCode = s.OperatorCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, SqlTemplate = s.SqlTemplate,
                             AppliesTo = s.AppliesTo, Arity = s.Arity, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (OperatorCode, Name, SqlTemplate, AppliesTo, Arity, SortOrder)
    VALUES (s.OperatorCode, s.Name, s.SqlTemplate, s.AppliesTo, s.Arity, s.SortOrder);
PRINT '  cfg.Operator                      seeded';
GO

/* ---------------------------------------------------------------------------------
   Settings — a cap, a page size, a weight total, a width.  Never a C# const.
   --------------------------------------------------------------------------------- */
MERGE cfg.Setting AS t
USING (VALUES
    (N'ATTAINMENT_SAMPLE_CAP',      NULL,          600.0,   N'Above this many people, design-time figures come off an evenly spaced sample and the panel says so.'),
    (N'PAGE_SIZE_DEFAULT',          NULL,          50.0,    N'Rows per page before the viewer chooses otherwise.'),
    (N'PAGE_SIZE_MAX',              NULL,          500.0,   N'The largest page a viewer may ask for.'),
    (N'WEIGHT_TOTAL_TARGET',        NULL,          100.0,   N'What a framework''s weights are expected to add up to.'),
    (N'CONTENT_MAX_WIDTH_PX',       NULL,          1600.0,  N'The content column stops widening here.'),
    (N'COMPARE_MAX',                NULL,          6.0,     N'How many candidates may be compared side by side.'),
    (N'VALIDATION_MAX_SHOWN',       NULL,          5.0,     N'How many to-dos the review step lists.'),
    (N'STAGE_LIST_MAX_DRAW',        NULL,          12000.0, N'Above this the table offers an export instead of drawing.'),
    (N'IDP_TARGET_MONTHS_PER_LEVEL',NULL,          6.0,     N'The target completion date tightens by this many months per readiness level.'),
    (N'AUTH_ENDING_MONTHS',         NULL,          4.0,     N'How far ahead an ending authorization is announced.'),
    (N'AS_OF_OVERRIDE',             NULL,          NULL,    N'Set a date here to run the whole application as if it were that day.'),
    (N'ROSTER_ACTIVE_VALUES',       N'Y,X,ACTIVE', NULL,    N'The values of ActiveInd that count as an active employee.')
) AS s (SettingKey, TextValue, NumValue, Description)
   ON t.SettingKey = s.SettingKey
WHEN MATCHED THEN UPDATE SET Description = s.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SettingKey, TextValue, NumValue, Description)
    VALUES (s.SettingKey, s.TextValue, s.NumValue, s.Description);
PRINT '  cfg.Setting                       seeded';
GO

/* ---------------------------------------------------------------------------------
   Messages — every user-visible sentence that can vary.  The ones marked verbatim are
   reused exactly as the prototype words them.
   --------------------------------------------------------------------------------- */
MERGE cfg.Message AS t
USING (VALUES
    (N'READONLY_REFUSAL',    N'Nothing was changed. Your role may read this screen but not write to it.', N'Verbatim.'),
    (N'CLOSED_CYCLE',        N'A closed cycle is never changed, only copied.', N'Verbatim.'),
    (N'SOURCE_UNMAPPED',     N'No table is mapped for this kind, so every requirement that names it can never be met.', N'Verbatim.'),
    (N'SAMPLED_FIGURES',     N'Estimated from a sample of {sample} of {total}.', N'Verbatim, with the two counts substituted.'),
    (N'SHARE_UNDER_ONE',     N'under 1%', N'A non-zero count that rounds to nothing.'),
    (N'SHARE_OVER_NINETY_NINE', N'over 99%', N'A count short of the total that rounds to everything.'),
    (N'NOT_OWNER_REFUSAL',   N'This design belongs to someone else. Only its owner, its delegate or an administrator may change it.', NULL),
    (N'ROSTER_UNMAPPED',     N'No roster table is mapped, so there is nobody to show. Map it on the Table mapping screen.', NULL),
    (N'AUTH_ENDED',          N'Authorization ended', NULL),
    (N'AUTH_ENDING',         N'Ends within four months', NULL),
    (N'WHY_MET',             N'Met', N'The fallback reason when there is no figure to quote.'),
    (N'WHY_NOT_TAKEN',       N'Not taken', N'Verbatim.'),
    (N'WHY_STARTED',         N'Started, not finished', N'Verbatim.'),
    (N'WHY_NO_ROW_MATCHED',  N'Recorded, but no row meets the conditions', N'Verbatim.'),
    (N'LADDER_HELD',         N'Held', NULL),
    (N'LADDER_SHORT',        N'Short of {pct}%', NULL),
    (N'LADDER_DISQUALIFIED', N'Disqualified', N'A must requirement not met disqualifies outright.'),
    (N'LADDER_NO_THRESHOLD', N'No percentage set', NULL),
    (N'POOL_EMPTY',          N'Nobody in the roster meets these criteria. Widen a set, or check the values.', N'Nobody qualifies — not the same as the question failing.'),
    (N'NO_CYCLES',           N'No cycles yet. Start a new design to create one.', NULL),
    (N'STAGE_NOT_OPEN',      N'This stage is read only because it is not open. The stage open now is {stage}.', NULL),
    (N'STAGE_CLOSED',        N'This stage closed on {date}. Stages close on their end date; there is no manual complete.', NULL),
    (N'STAGE_FUTURE',        N'This stage opens on {date}.', NULL),
    (N'STAGE_UNDATED',       N'This stage has no window, so it never opens. Set its dates on step 5 of the design.', NULL),
    (N'SEATS_LEFT',          N'That session has {left} place{s} left, and you selected {asked}.', NULL),
    (N'IDP_COVERAGE_MANUAL', N'Coverage costs leave, so it is never assigned automatically.', NULL),
    (N'IDP_NOT_READY',       N'Every open requirement needs a booking, a date or coverage days before this plan can be approved.', NULL),
    (N'SENSITIVE_FILTER',    N'This is a sensitive field. It can be read on a person''s record but not used as a filter.', NULL),
    (N'SUGGESTIONS_ADVISORY',N'These are suggestions only. Nothing here is recorded until you decide it yourself.', NULL),
    (N'TEST_MODE_ON',        N'Test mode ignores every stage window, and stamps each decision TEST in the log.', NULL)
) AS s (MessageKey, MessageText, Description)
   ON t.MessageKey = s.MessageKey
WHEN MATCHED THEN UPDATE SET MessageText = s.MessageText, Description = s.Description
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MessageKey, MessageText, Description) VALUES (s.MessageKey, s.MessageText, s.Description);
PRINT '  cfg.Message                       seeded';
GO

/* ---------------------------------------------------------------------------------
   Navigation — the groups and captions the prototype ships, with what each is for.
   --------------------------------------------------------------------------------- */
MERGE cfg.MenuGroup AS t
USING (VALUES
    (N'SUCCESSION',    N'Succession',    N'what you do',                        10),
    (N'CONFIGURATION', N'Configuration', N'what a cycle is built out of',        20),
    (N'REPORTS',       N'Reports',       N'what the cycle says so far',          30),
    (N'ACCESS',        N'Access',        N'who may see what',                    40)
) AS s (GroupCode, Caption, Subtitle, SortOrder)
   ON t.GroupCode = s.GroupCode
WHEN MATCHED THEN UPDATE SET Caption = s.Caption, Subtitle = s.Subtitle, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (GroupCode, Caption, Subtitle, SortOrder) VALUES (s.GroupCode, s.Caption, s.Subtitle, s.SortOrder);
PRINT '  cfg.MenuGroup                     seeded';
GO

/* Screens.  ScreenCode is the shipped route path — the legacy policy rows are keyed on
   these, so they are data and not a naming convention we may change.
   Stage screens are faces of a cycle: IsInMenu = 0.                                    */
MERGE cfg.Screen AS t
USING (VALUES
    (N'/Selection/Cycles/',      N'Cycles',                  N'Selection', N'Cycles',      N'Index', N'SUCCESSION',    1, 10),
    (N'/Selection/Employees/',   N'Employee roster',         N'Selection', N'Employees',   N'Index', N'SUCCESSION',    1, 20),
    (N'/Selection/CycleSetup/',  N'Cycle design',            N'Selection', N'CycleSetup',  N'Index', N'CONFIGURATION', 1, 10),
    (N'/Selection/Setup/',       N'Development framework',   N'Config',    N'DevFramework',N'Index', N'CONFIGURATION', 1, 20),
    (N'/Config/RosterFields/',   N'Roster fields',           N'Config',    N'RosterFields',N'Index', N'CONFIGURATION', 1, 30),
    (N'/Config/TableMapping/',   N'Table mapping',           N'Config',    N'TableMapping',N'Index', N'CONFIGURATION', 1, 40),
    (N'/Config/RefData/',        N'Reference data',          N'Config',    N'RefData',     N'Index', N'CONFIGURATION', 1, 50),
    (N'/Selection/Reports/',     N'Reports',                 N'Selection', N'Reports',     N'Index', N'REPORTS',       1, 10),
    (N'/Selection/Audit/',       N'Decision log',            N'Selection', N'Audit',       N'Index', N'REPORTS',       1, 20),
    (N'/Admin/Policy/',          N'Access control',          N'Admin',     N'Policy',      N'Index', N'ACCESS',        1, 10),
    (N'/Admin/Rls/',             N'Row-level security',      N'Admin',     N'Rls',         N'Index', N'ACCESS',        1, 20),
    (N'/Admin/LoadExceptions/',  N'Load exceptions',         N'Admin',     N'LoadExceptions', N'Index', N'ACCESS',     1, 30),
    /* Stage screens — reached from the cycle, never from the menu. */
    (N'/Selection/Identify/',    N'Identify',                N'Selection', N'Identify',    N'Index', NULL, 0, 100),
    (N'/Selection/Review/',      N'Review',                  N'Selection', N'Review',      N'Index', NULL, 0, 110),
    (N'/Selection/Calibrate/',   N'Calibration',             N'Selection', N'Calibrate',   N'Index', NULL, 0, 120),
    (N'/Selection/SuccessionIdentify/',  N'Succession identify',  N'Selection', N'SuccessionIdentify',  N'Index', NULL, 0, 130),
    (N'/Selection/SuccessionReview/',    N'Succession review',    N'Selection', N'SuccessionReview',    N'Index', NULL, 0, 140),
    (N'/Selection/SuccessionCalibrate/', N'Succession calibration', N'Selection', N'SuccessionCalibrate', N'Index', NULL, 0, 150),
    (N'/Selection/Develop/',     N'Development',             N'Selection', N'Develop',     N'Index', NULL, 0, 160),
    (N'/Selection/Compare/',     N'Compare',                 N'Selection', N'Compare',     N'Index', NULL, 0, 170),
    (N'/Selection/Profile/',     N'Profile',                 N'Selection', N'Profile',     N'Index', NULL, 0, 180),
    (N'/Admin/Health/',          N'Health',                  N'Admin',     N'Health',      N'Index', NULL, 0, 190)
) AS s (ScreenCode, Name, AreaName, ControllerName, ActionName, GroupCode, IsInMenu, SortOrder)
   ON t.ScreenCode = s.ScreenCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, AreaName = s.AreaName, ControllerName = s.ControllerName,
                             ActionName = s.ActionName, IsInMenu = s.IsInMenu, SortOrder = s.SortOrder,
                             MenuGroupId = (SELECT MenuGroupId FROM cfg.MenuGroup g WHERE g.GroupCode = s.GroupCode)
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ScreenCode, Name, AreaName, ControllerName, ActionName, MenuGroupId, IsInMenu, SortOrder)
    VALUES (s.ScreenCode, s.Name, s.AreaName, s.ControllerName, s.ActionName,
            (SELECT MenuGroupId FROM cfg.MenuGroup g WHERE g.GroupCode = s.GroupCode), s.IsInMenu, s.SortOrder);
PRINT '  cfg.Screen                        seeded';
GO

/* ---------------------------------------------------------------------------------
   Requirement kinds and where their evidence lives
   --------------------------------------------------------------------------------- */
MERGE sel.RequirementKind AS t
USING (VALUES
    (N'COURSE',      N'Course',          N'FLAG', N'MEASURE', N'Met when a completion row for the item exists with status Completed.', 10),
    (N'ASSESSMENT',  N'Assessment',      N'FLAG', N'MEASURE', N'Met when an assessment result for the item reaches its pass value.',   20),
    (N'FEEDBACK360', N'360 feedback',    N'FLAG', N'MEASURE', N'Met when a survey result for the item reaches its pass value.',        30),
    (N'COVERAGE',    N'Coverage days',   N'SUM',  N'MEASURE', N'Met when the days summed over the matching coverage rows reach the floor.', 40),
    (N'EXPERIENCE',  N'Experience',      N'SUM',  N'MEASURE', N'Met when the months summed over the matching assignment rows reach the floor.', 50)
) AS s (KindCode, Name, EvalModeCode, MeasureDomain, DefaultRuleText, SortOrder)
   ON t.KindCode = s.KindCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, EvalModeCode = s.EvalModeCode,
                             DefaultRuleText = s.DefaultRuleText, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (KindCode, Name, EvalModeCode, MeasureDomain, DefaultRuleText, SortOrder)
    VALUES (s.KindCode, s.Name, s.EvalModeCode, s.MeasureDomain, s.DefaultRuleText, s.SortOrder);
PRINT '  sel.RequirementKind               seeded';
GO

/* ---------------------------------------------------------------------------------
   Table mapping — every table the application reads is named here, with what reads it
   and what breaks when it is absent.  IsMapped is set by discovery, never by hand.
   --------------------------------------------------------------------------------- */
MERGE sel.TableMapping AS t
USING (VALUES
 (N'ROSTER',     N'Employee roster',        N'ManpowerPermanent_AllRecords', N'PersonnelNo', NULL,
  N'every candidate, criterion and list', N'No pool can be resolved; the application has nobody to show.', 1, 10),
 (N'DIRECTORY',  N'Employee directory',     N'EmployeeDirectory',            N'PersonnelNo', NULL,
  N'owner and delegate search', N'No delegate can be named.', 0, 20),
 (N'PLAN',       N'Succession plan',        N'SuccessionPlan',               N'EmployeeId',  N'Department',
  N'succession identify and review', N'Every candidate looks new — no history.', 0, 30),
 (N'POSITION',   N'Position',               N'Position',                     N'IncumbentId', N'PositionCode',
  N'by-position view and incumbent advisory', N'No positions, and no successors named.', 0, 40),
 (N'POOL',       N'Pool membership',        N'PoolMembership',               N'EmployeeId',  N'PoolCode',
  N'existing-pool carry-in', N'Last year''s pool cannot be carried.', 0, 50),
 (N'COURSE',     N'Course completion',      N'CourseCompletion',             N'EmployeeId',  N'CourseId',
  N'COURSE evidence', N'Course requirements can never be met.', 0, 60),
 (N'ASSESSMENT', N'Assessment result',      N'AssessmentResult',             N'EmployeeId',  N'AssessmentId',
  N'ASSESSMENT evidence', N'Assessment requirements can never be met.', 0, 70),
 (N'FEEDBACK360',N'Survey result',          N'SurveyResult',                 N'EmployeeId',  N'SurveyId',
  N'360 evidence', N'360 requirements can never be met.', 0, 80),
 (N'EXPERIENCE', N'Employee coverage',      N'EmployeeCoverage',             N'EmployeeId',  N'PositionSuffix',
  N'coverage days', N'Acting and coverage requirements can never be met.', 0, 90),
 (N'JOBCERT',    N'Job certification',      N'EmployeeJobCertification',     N'EmployeeId',  N'CurriculumCode',
  N'development identify', N'No curriculum to propose.', 0, 100),
 (N'CUSTOMCUR',  N'Custom curriculum',      N'EmployeeCustomCurriculum',     N'EmployeeId',  N'CurriculumCode',
  N'development identify', N'Custom curricula are invisible.', 0, 110),
 (N'MANDTRAIN',  N'Mandatory training',     N'EmployeeMandatoryTraining',    N'EmployeeId',  N'CurriculumCode',
  N'development identify', N'Mandatory training is invisible.', 0, 120),
 (N'LEADPROG',   N'Leadership programme',   N'EmployeeLeadershipProgramme',  N'EmployeeId',  N'ProgrammeCode',
  N'development identify', N'Leadership programmes are invisible.', 0, 130),
 (N'PMP',        N'Performance rating',     N'EmployeePmp',                  N'EmployeeId',  NULL,
  N'profile and the three-year average', N'No performance history is shown.', 0, 140)
) AS s (SourceKey, Caption, TableName, KeyColumn, ItemColumn, ReadBy, BreaksWhenUnmapped, IsRequired, SortOrder)
   ON t.SourceKey = s.SourceKey
WHEN MATCHED THEN UPDATE SET Caption = s.Caption, ReadBy = s.ReadBy,
                             BreaksWhenUnmapped = s.BreaksWhenUnmapped,
                             IsRequired = s.IsRequired, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (SourceKey, Caption, SchemaName, TableName, KeyColumn, ItemColumn, ReadBy,
            BreaksWhenUnmapped, IsRequired, SortOrder)
    VALUES (s.SourceKey, s.Caption, N'dbo', s.TableName, s.KeyColumn, s.ItemColumn, s.ReadBy,
            s.BreaksWhenUnmapped, s.IsRequired, s.SortOrder);
PRINT '  sel.TableMapping                  seeded';
GO

/* Evidence sources — one per kind, pointing at the application's own copy, and naming
   the source it is loaded from.                                                       */
MERGE sel.EvidenceSource AS t
USING (VALUES
    (N'COURSE',      N'COURSE',      N'sel', N'EmployeeRecord',   N'PersonnelNo', N'ItemCode', N'Status', N'Completed', NULL),
    (N'ASSESSMENT',  N'ASSESSMENT',  N'sel', N'EmployeeRecord',   N'PersonnelNo', N'ItemCode', N'Status', N'Completed', N'Score'),
    (N'FEEDBACK360', N'FEEDBACK360', N'sel', N'EmployeeRecord',   N'PersonnelNo', N'ItemCode', N'Status', N'Completed', N'Score'),
    (N'COVERAGE',    N'EXPERIENCE',  N'sel', N'EmployeeCoverage', N'PersonnelNo', N'ItemCode', NULL,      NULL,         N'Days'),
    (N'EXPERIENCE',  N'EXPERIENCE',  N'sel', N'EmployeeCoverage', N'PersonnelNo', N'ItemCode', NULL,      NULL,         N'Months')
) AS s (KindCode, SourceKey, AppSchema, AppTable, KeyColumn, ItemColumn, StatusColumn, PassValue, MeasureColumn)
   ON t.KindCode = s.KindCode
WHEN MATCHED THEN UPDATE SET SourceKey = s.SourceKey, AppSchema = s.AppSchema, AppTable = s.AppTable,
                             KeyColumn = s.KeyColumn, ItemColumn = s.ItemColumn,
                             StatusColumn = s.StatusColumn, PassValue = s.PassValue,
                             MeasureColumn = s.MeasureColumn,
                             /* The application's own tables always exist once 03 has run. */
                             IsMapped = 1
WHEN NOT MATCHED BY TARGET THEN
    INSERT (KindCode, SourceKey, AppSchema, AppTable, KeyColumn, ItemColumn, StatusColumn,
            PassValue, MeasureColumn, IsMapped)
    VALUES (s.KindCode, s.SourceKey, s.AppSchema, s.AppTable, s.KeyColumn, s.ItemColumn,
            s.StatusColumn, s.PassValue, s.MeasureColumn, 1);
PRINT '  sel.EvidenceSource                seeded';
GO

/* The fields a completion condition may name, before anybody has typed one. */
MERGE sel.EvidenceSourceColumn AS t
USING (
    SELECT es.EvidenceSourceId, c.ColumnName, c.Caption, c.DataType, c.IsExpiryDate, c.SortOrder
    FROM sel.EvidenceSource es
    CROSS APPLY (VALUES
        (N'Status',      N'Status',            N'text',   CAST(0 AS bit), 10),
        (N'Score',       N'Score',             N'number', CAST(0 AS bit), 20),
        (N'MaxScore',    N'Maximum score',     N'number', CAST(0 AS bit), 30),
        (N'CompletedOn', N'Completed on',      N'date',   CAST(0 AS bit), 40),
        (N'StartedOn',   N'Started on',        N'date',   CAST(0 AS bit), 50),
        (N'ExpiresOn',   N'Expires on',        N'date',   CAST(1 AS bit), 60),
        (N'AttemptNo',   N'Attempt number',    N'number', CAST(0 AS bit), 70)
    ) c (ColumnName, Caption, DataType, IsExpiryDate, SortOrder)
    WHERE es.AppTable = N'EmployeeRecord'
    UNION ALL
    SELECT es.EvidenceSourceId, c.ColumnName, c.Caption, c.DataType, c.IsExpiryDate, c.SortOrder
    FROM sel.EvidenceSource es
    CROSS APPLY (VALUES
        (N'CoverageType',   N'Coverage type',    N'text',   CAST(0 AS bit), 10),
        (N'Department',     N'Department',       N'text',   CAST(0 AS bit), 20),
        (N'OrgCode',        N'Organisation',     N'text',   CAST(0 AS bit), 30),
        (N'PositionSuffix', N'Position suffix',  N'text',   CAST(0 AS bit), 40),
        (N'PositionCode',   N'Position code',    N'text',   CAST(0 AS bit), 50),
        (N'StartDate',      N'Start date',       N'date',   CAST(0 AS bit), 60),
        (N'EndDate',        N'End date',         N'date',   CAST(1 AS bit), 70),
        (N'Days',           N'Days',             N'number', CAST(0 AS bit), 80),
        (N'Months',         N'Months',           N'number', CAST(0 AS bit), 90)
    ) c (ColumnName, Caption, DataType, IsExpiryDate, SortOrder)
    WHERE es.AppTable = N'EmployeeCoverage'
) AS s
   ON t.EvidenceSourceId = s.EvidenceSourceId AND t.ColumnName = s.ColumnName
WHEN MATCHED THEN UPDATE SET Caption = s.Caption, DataType = s.DataType,
                             IsExpiryDate = s.IsExpiryDate, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (EvidenceSourceId, ColumnName, Caption, DataType, IsExpiryDate, IsPhysical, IsLearned, SortOrder)
    VALUES (s.EvidenceSourceId, s.ColumnName, s.Caption, s.DataType, s.IsExpiryDate, 1, 0, s.SortOrder);
PRINT '  sel.EvidenceSourceColumn          seeded';
GO

/* Derived per-person figures the criteria builder may filter on. */
MERGE sel.MetricDefinition AS t
USING (VALUES
    (N'DaysCovered',        N'Coverage days',                N'Total days of recorded coverage.',              N'number', 10),
    (N'PerformanceAvg3',    N'Three-year performance',       N'Average of the last three recorded years.',     N'number', 20),
    (N'CoursesCompleted',   N'Courses completed',            N'How many course completions are recorded.',     N'number', 30),
    (N'DirectorActingDays', N'Director acting days',         N'Days acting against a position suffix.',        N'number', 40),
    (N'TenureYears',        N'Tenure in years',              N'Years since the hire date, against the as-of date.', N'number', 50)
) AS s (MetricKey, Name, Description, DataType, SortOrder)
   ON t.MetricKey = s.MetricKey
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MetricKey, Name, Description, DataType, SortOrder)
    VALUES (s.MetricKey, s.Name, s.Description, s.DataType, s.SortOrder);
PRINT '  sel.MetricDefinition              seeded';
GO

/* ---------------------------------------------------------------------------------
   Processes, stages, wizard, recipes, validation
   --------------------------------------------------------------------------------- */
MERGE sel.ProcessType AS t
USING (VALUES
    (N'TALENT_REVIEW', N'Talent review', N'Identify, review and calibrate a pool of people.', 0, 10),
    (N'SUCCESSION',    N'Succession',    N'Plan named successors against departments and positions.', 0, 20),
    (N'DEVELOPMENT',   N'Development',   N'Turn unmet requirements into booked, dated plans.', 0, 30),
    (N'CUSTOM',        N'Custom',        N'A process of your own, with stages you name.', 1, 40)
) AS s (ProcessTypeCode, Name, Description, AllowsRepeat, SortOrder)
   ON t.ProcessTypeCode = s.ProcessTypeCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             AllowsRepeat = s.AllowsRepeat, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProcessTypeCode, Name, Description, AllowsRepeat, SortOrder)
    VALUES (s.ProcessTypeCode, s.Name, s.Description, s.AllowsRepeat, s.SortOrder);
PRINT '  sel.ProcessType                   seeded';
GO

MERGE sel.StageKind AS t
USING (VALUES
    (N'TR_IDENTIFY',  N'TALENT_REVIEW', N'Identify',                    N'Identify',            N'/Selection/Identify/',  10),
    (N'TR_REVIEW',    N'TALENT_REVIEW', N'Review',                      N'Review',              N'/Selection/Review/',    20),
    (N'TR_CALIBRATE', N'TALENT_REVIEW', N'Calibration',                 N'Calibrate',           N'/Selection/Calibrate/', 30),
    (N'SU_IDENTIFY',  N'SUCCESSION',    N'Identify',                    N'SuccessionIdentify',  N'/Selection/SuccessionIdentify/',  10),
    (N'SU_REVIEW',    N'SUCCESSION',    N'Review',                      N'SuccessionReview',    N'/Selection/SuccessionReview/',    20),
    (N'SU_CALIBRATE', N'SUCCESSION',    N'Calibration',                 N'SuccessionCalibrate', N'/Selection/SuccessionCalibrate/', 30),
    (N'DV_IDENTIFY',  N'DEVELOPMENT',   N'Identify',                    N'Develop',             N'/Selection/Develop/',   10),
    (N'DV_REVIEW',    N'DEVELOPMENT',   N'Review',                      N'Develop',             N'/Selection/Develop/',   20),
    (N'DV_IDP',       N'DEVELOPMENT',   N'Individual development plan', N'Idp',                 N'/Selection/Develop/',   30),
    (N'CU_STAGE',     N'CUSTOM',        N'Stage',                       N'Develop',             N'/Selection/Develop/',   10)
) AS s (StageKindCode, ProcessTypeCode, Name, RouteKey, ScreenCode, SortOrder)
   ON t.StageKindCode = s.StageKindCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, RouteKey = s.RouteKey,
                             ScreenCode = s.ScreenCode, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StageKindCode, ProcessTypeCode, Name, RouteKey, ScreenCode, SortOrder)
    VALUES (s.StageKindCode, s.ProcessTypeCode, s.Name, s.RouteKey, s.ScreenCode, s.SortOrder);
PRINT '  sel.StageKind                     seeded';
GO

/* Six steps are seeded; nothing in the application may assume there are six. */
MERGE sel.WizardStep AS t
USING (VALUES
    (1, N'CYCLE',     N'The cycle',             N'Code, name, window, owner, delegate and the existing pool link.', 0, 10),
    (2, N'POOL',      N'Eligible pool',         N'Who this cycle is about, as criteria over the roster.', 1, 20),
    (3, N'FRAMEWORK', N'Development framework', N'What the cycle asks people to have done.', 1, 30),
    (4, N'READINESS', N'Readiness levels',      N'How much of that framework is enough, per level.', 1, 40),
    (5, N'STAGES',    N'Stages',                N'Which processes run, when, and who performs each stage.', 1, 50),
    (6, N'REVIEW',    N'Review and open',       N'The design read back, and what is still unfinished.', 0, 60)
) AS s (StepNo, StepCode, Caption, Description, IsSkippable, SortOrder)
   ON t.StepNo = s.StepNo
WHEN MATCHED THEN UPDATE SET StepCode = s.StepCode, Caption = s.Caption, Description = s.Description,
                             IsSkippable = s.IsSkippable, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (StepNo, StepCode, Caption, Description, IsSkippable, SortOrder)
    VALUES (s.StepNo, s.StepCode, s.Caption, s.Description, s.IsSkippable, s.SortOrder);
PRINT '  sel.WizardStep                    seeded';
GO

/* Recipes — "New design" never opens an empty form. */
MERGE sel.CycleRecipe AS t
USING (VALUES
    (N'TALENT_CYCLE', N'Talent Cycle',
     N'Identify, review and calibrate a pool, then plan successors against it. Asks which job suffixes it covers.', 1, 0, 10),
    (N'START_NEW',    N'Start New',
     N'A blank design. Nothing is assumed, and no job suffix is asked for unless a succession process is added later.', 0, 0, 20),
    (N'COPY',         N'Copy a cycle you can see',
     N'Carry a design, its criteria, levels, processes, frameworks and pool rules forward as a new draft.', 0, 1, 30)
) AS s (RecipeCode, Name, Description, AsksJobSuffix, IsCopy, SortOrder)
   ON t.RecipeCode = s.RecipeCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             AsksJobSuffix = s.AsksJobSuffix, IsCopy = s.IsCopy, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (RecipeCode, Name, Description, AsksJobSuffix, IsCopy, SortOrder)
    VALUES (s.RecipeCode, s.Name, s.Description, s.AsksJobSuffix, s.IsCopy, s.SortOrder);
PRINT '  sel.CycleRecipe                   seeded';
GO

/* A Talent Cycle inserts a talent-review process and a succession process, and marks the
   steps it does not need as skipped — so a common cycle opens in three steps, not six. */
MERGE sel.CycleRecipeProcess AS t
USING (SELECT r.RecipeId, x.ProcessTypeCode, x.Name, x.SortOrder
       FROM sel.CycleRecipe r
       CROSS APPLY (VALUES
            (N'TALENT_REVIEW', N'Talent review', 10),
            (N'SUCCESSION',    N'Succession',    20)
       ) x (ProcessTypeCode, Name, SortOrder)
       WHERE r.RecipeCode = N'TALENT_CYCLE') AS s
   ON t.RecipeId = s.RecipeId AND t.ProcessTypeCode = s.ProcessTypeCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (RecipeId, ProcessTypeCode, Name, SortOrder)
    VALUES (s.RecipeId, s.ProcessTypeCode, s.Name, s.SortOrder);
PRINT '  sel.CycleRecipeProcess            seeded';
GO

MERGE sel.CycleRecipeSkip AS t
USING (SELECT r.RecipeId, x.StepNo
       FROM sel.CycleRecipe r
       CROSS APPLY (VALUES (3), (4)) x (StepNo)
       WHERE r.RecipeCode = N'TALENT_CYCLE') AS s
   ON t.RecipeId = s.RecipeId AND t.StepNo = s.StepNo
WHEN NOT MATCHED BY TARGET THEN INSERT (RecipeId, StepNo) VALUES (s.RecipeId, s.StepNo);
PRINT '  sel.CycleRecipeSkip               seeded';
GO

/* Validation — every sentence the review step shows lives here, not in an attribute. */
MERGE sel.ValidationRule AS t
USING (VALUES
 (N'CYCLE_NO_NAME',          1, N'This cycle has no name yet.', N'BLOCK', 10),
 (N'CYCLE_NO_WINDOW',        1, N'Set a start and an end date, so the stages can be scheduled.', N'BLOCK', 20),
 (N'CYCLE_WINDOW_BACKWARDS', 1, N'The end date is before the start date.', N'BLOCK', 30),
 (N'CYCLE_NO_OWNER',         1, N'This design has no owner, so nobody can be held to it.', N'BLOCK', 40),
 (N'POOL_NO_SET',            2, N'No criteria are set, so the pool would be the whole roster.', N'BLOCK', 50),
 (N'POOL_UNFINISHED_VALUE',  2, N'A criterion is missing a value.', N'BLOCK', 60),
 (N'POOL_LINK_UNMAPPED',     2, N'An existing pool is linked, but no membership table is mapped.', N'BLOCK', 70),
 (N'FRAMEWORK_NONE',         3, N'No development framework is assigned, so nothing is being asked for.', N'BLOCK', 80),
 (N'FRAMEWORK_DRAFT',        3, N'A framework assigned to this cycle is still a draft.', N'BLOCK', 90),
 (N'FRAMEWORK_EMPTY',        3, N'A framework assigned to this cycle has no events in it.', N'BLOCK', 100),
 (N'FRAMEWORK_RETIRED',      3, N'A framework assigned to this cycle has been retired.', N'BLOCK', 110),
 (N'READINESS_NO_NAME',      4, N'A readiness level is missing its code or its name.', N'BLOCK', 120),
 (N'READINESS_NO_PCT',       4, N'A readiness level has no percentage, so nobody can reach it.', N'BLOCK', 130),
 (N'READINESS_DUP_PCT',      4, N'Two readiness levels share the same percentage.', N'BLOCK', 140),
 (N'READINESS_NO_EVENTS',    4, N'There are readiness levels but no framework contributing events to measure against.', N'BLOCK', 150),
 (N'STAGE_NO_PROCESS',       5, N'No process is set up, so this cycle has nothing to run.', N'BLOCK', 160),
 (N'STAGE_NO_STAGES',        5, N'A process has no stages.', N'BLOCK', 170),
 (N'STAGE_NO_WINDOW',        5, N'A stage has no window, so it never opens.', N'BLOCK', 180),
 (N'STAGE_OUTSIDE_CYCLE',    5, N'A stage falls outside the cycle window.', N'BLOCK', 190),
 (N'STAGE_OVERLAP',          5, N'Two stages of the same process overlap.', N'BLOCK', 200),
 (N'STAGE_NO_PERFORMER',     5, N'A stage does not say who performs it.', N'BLOCK', 210)
) AS s (RuleCode, StepNo, Sentence, Severity, SortOrder)
   ON t.RuleCode = s.RuleCode
WHEN MATCHED THEN UPDATE SET StepNo = s.StepNo, Sentence = s.Sentence,
                             Severity = s.Severity, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (RuleCode, StepNo, Sentence, Severity, SortOrder)
    VALUES (s.RuleCode, s.StepNo, s.Sentence, s.Severity, s.SortOrder);
PRINT '  sel.ValidationRule                seeded';
GO

/* The preset readiness ladder a new design starts from. */
MERGE sel.ReadinessLevel AS t
USING (VALUES
    (N'R1', N'Ready now',            N'Ready to take the role today.',            90.0, 10),
    (N'R2', N'Ready in 1–2 years',   N'Ready with a short run of development.',   75.0, 20),
    (N'R3', N'Ready in 3–5 years',   N'Ready with a longer run of development.',  60.0, 30),
    (N'R4', N'Longer term',          N'A candidate for the role eventually.',     40.0, 40),
    (N'R5', N'Lateral',              N'A move across rather than up.',            25.0, 50)
) AS s (LevelCode, Name, Description, ThresholdPct, SortOrder)
   ON t.LevelCode = s.LevelCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             ThresholdPct = s.ThresholdPct, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (LevelCode, Name, Description, ThresholdPct, SortOrder)
    VALUES (s.LevelCode, s.Name, s.Description, s.ThresholdPct, s.SortOrder);
PRINT '  sel.ReadinessLevel                seeded';
GO

/* Mixture models. */
MERGE sel.MixtureModel AS t
USING (VALUES
    (N'70_20_10', N'70 / 20 / 10', N'Experience-led: most learning on the job.', 5.0, 10),
    (N'40_40_20', N'40 / 40 / 20', N'Balanced between experience and assessment.', 5.0, 20)
) AS s (ModelCode, Name, Description, TolerancePct, SortOrder)
   ON t.ModelCode = s.ModelCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             TolerancePct = s.TolerancePct, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ModelCode, Name, Description, TolerancePct, SortOrder)
    VALUES (s.ModelCode, s.Name, s.Description, s.TolerancePct, s.SortOrder);
GO

MERGE sel.MixturePart AS t
USING (SELECT m.MixtureModelId,
              PartValueId = cfg.fn_DomainValueId(N'PART', x.PartCode),
              x.TargetPct, x.SortOrder
       FROM sel.MixtureModel m
       CROSS APPLY (VALUES
            (N'70_20_10', N'EXPERIENCE', 70.0, 10), (N'70_20_10', N'ASSESSMENT', 20.0, 20), (N'70_20_10', N'COURSE', 10.0, 30),
            (N'40_40_20', N'EXPERIENCE', 40.0, 10), (N'40_40_20', N'ASSESSMENT', 40.0, 20), (N'40_40_20', N'COURSE', 20.0, 30)
       ) x (ModelCode, PartCode, TargetPct, SortOrder)
       WHERE x.ModelCode = m.ModelCode) AS s
   ON t.MixtureModelId = s.MixtureModelId AND t.PartValueId = s.PartValueId
WHEN MATCHED THEN UPDATE SET TargetPct = s.TargetPct, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (MixtureModelId, PartValueId, TargetPct, SortOrder)
    VALUES (s.MixtureModelId, s.PartValueId, s.TargetPct, s.SortOrder);
PRINT '  sel.MixtureModel / MixturePart    seeded';
GO

/* ---------------------------------------------------------------------------------
   Roles, the bootstrap administrator, and the prototype's four viewers
   --------------------------------------------------------------------------------- */
MERGE sec.Role AS t
USING (VALUES
    (N'ADMIN',   N'Administrator',         N'Configures the application and may edit any design.', 0, 10),
    (N'HRBP',    N'HR Business Partner',   N'Runs cycles within the organisations they are granted.', 0, 20),
    (N'SVP',     N'Senior Vice President', N'Decides at senior-vice-president level within their organisations.', 0, 30),
    (N'AUDITOR', N'Auditor',               N'Reads everything and changes nothing.', 1, 40)
) AS s (RoleCode, Name, Description, IsReadOnly, SortOrder)
   ON t.RoleCode = s.RoleCode
WHEN MATCHED THEN UPDATE SET Name = s.Name, Description = s.Description,
                             IsReadOnly = s.IsReadOnly, SortOrder = s.SortOrder
WHEN NOT MATCHED BY TARGET THEN
    INSERT (RoleCode, Name, Description, IsReadOnly, SortOrder)
    VALUES (s.RoleCode, s.Name, s.Description, s.IsReadOnly, s.SortOrder);
PRINT '  sec.Role                          seeded';
GO

MERGE sec.AppUser AS t
USING (VALUES
    (N'maseera.admin',   N'Maseera Administrator',  1, 1),
    (N'maseera.hrbp',    N'Layla Al Mansouri',      0, 1),
    (N'maseera.svp',     N'Omar Al Harthy',         0, 1),
    (N'maseera.auditor', N'Internal Audit',         0, 1)
) AS s (LoginName, DisplayName, IsBootstrap, IsActive)
   ON t.LoginName = s.LoginName
WHEN MATCHED THEN UPDATE SET DisplayName = s.DisplayName, IsBootstrap = s.IsBootstrap
WHEN NOT MATCHED BY TARGET THEN
    INSERT (LoginName, DisplayName, IsBootstrap, IsActive, AddedByLogin)
    VALUES (s.LoginName, s.DisplayName, s.IsBootstrap, s.IsActive, N'system');
PRINT '  sec.AppUser                       seeded';
GO

MERGE sec.UserRole AS t
USING (SELECT u.AppUserId, r.RoleId
       FROM (VALUES (N'maseera.admin', N'ADMIN'), (N'maseera.hrbp', N'HRBP'),
                    (N'maseera.svp', N'SVP'), (N'maseera.auditor', N'AUDITOR')) x (LoginName, RoleCode)
       JOIN sec.AppUser u ON u.LoginName = x.LoginName
       JOIN sec.Role r ON r.RoleCode = x.RoleCode) AS s
   ON t.AppUserId = s.AppUserId AND t.RoleId = s.RoleId
WHEN NOT MATCHED BY TARGET THEN INSERT (AppUserId, RoleId) VALUES (s.AppUserId, s.RoleId);
PRINT '  sec.UserRole                      seeded';
GO

/* Role grants.  The auditor is granted read on every screen; the read-only flag on the
   role is what stops any of it becoming write, so this cannot be widened by mistake.   */
MERGE sec.RoleScreenGrant AS t
USING (
    /* Administrator: write everywhere. */
    SELECT r.RoleId, s.ScreenId, GrantValue = 2
    FROM sec.Role r CROSS JOIN cfg.Screen s WHERE r.RoleCode = N'ADMIN'
    UNION ALL
    /* Auditor: read everywhere. */
    SELECT r.RoleId, s.ScreenId, 1
    FROM sec.Role r CROSS JOIN cfg.Screen s WHERE r.RoleCode = N'AUDITOR'
    UNION ALL
    /* HR Business Partner: runs cycles, configures the framework, reads reports;
       no access to the access-control screens. */
    SELECT r.RoleId, s.ScreenId,
           CASE WHEN s.ScreenCode LIKE N'/Admin/%' THEN 0 ELSE 2 END
    FROM sec.Role r CROSS JOIN cfg.Screen s WHERE r.RoleCode = N'HRBP'
    UNION ALL
    /* Senior Vice President: decides in the stages, reads the rest. */
    SELECT r.RoleId, s.ScreenId,
           CASE WHEN s.ScreenCode LIKE N'/Admin/%' THEN 0
                WHEN s.ScreenCode LIKE N'/Config/%' THEN 1
                WHEN s.ScreenCode = N'/Selection/CycleSetup/' THEN 1
                WHEN s.ScreenCode = N'/Selection/Setup/' THEN 1
                ELSE 2 END
    FROM sec.Role r CROSS JOIN cfg.Screen s WHERE r.RoleCode = N'SVP'
) AS s
   ON t.RoleId = s.RoleId AND t.ScreenId = s.ScreenId
WHEN MATCHED THEN UPDATE SET GrantValue = s.GrantValue
WHEN NOT MATCHED BY TARGET THEN INSERT (RoleId, ScreenId, GrantValue) VALUES (s.RoleId, s.ScreenId, s.GrantValue);
PRINT '  sec.RoleScreenGrant               seeded';
GO

/* The administrator sees every organisation, explicitly and auditably. */
MERGE sec.RlsBypass AS t
USING (SELECT AppUserId, Reason = N'Administrator: configures the application across every organisation.'
       FROM sec.AppUser WHERE LoginName = N'maseera.admin') AS s
   ON t.AppUserId = s.AppUserId
WHEN NOT MATCHED BY TARGET THEN
    INSERT (AppUserId, Reason, GrantedByLogin) VALUES (s.AppUserId, s.Reason, N'system');
PRINT '  sec.RlsBypass                     seeded';
GO

PRINT '== 09_reference_data complete ========================================';
GO
