/* =====================================================================================
   00_run_all.sql  —  the whole schema, in order, with a receipt
   -------------------------------------------------------------------------------------
   Run it against DB02:

       sqlcmd -S <server> -d DB02 -b -i db/00_run_all.sql

   This file uses :r to pull in 01-14, which is a SQLCMD command.  It therefore runs
   under the sqlcmd tool, or under SSMS with SQLCMD mode switched on (Query > SQLCMD
   Mode).  To open it in SSMS and simply press F5, use dist/maseera-schema.sql instead:
   the same content, flattened, with no commands in it.

   Every file is idempotent.  Running this a second time changes nothing and prints
   "skipped" against each object that was already there.

   The receipt at the end is the check: every Configuration and Reference count must be
   non-zero, and on a fresh database every Business count must be zero.
   ===================================================================================== */
:on error exit

/* QUOTED_IDENTIFIER is set here rather than left to whoever runs the file, because the
   two clients disagree about it.  SSMS connects with it ON; sqlcmd connects with it OFF
   unless it is given -I.  sel.SavedView has two filtered indexes, and a filtered index
   cannot be created with it off — so without this line the run dies two thirds of the
   way through, in SSMS never and from a command line always, which is a miserable thing
   to debug.

   It persists for the session, so once is enough, and every procedure below is created
   under it. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

/* There is one database and its name is DB02.  NOEXEC rather than a hard error: it stops
   the rest of the file whichever client is running it, and needs no special rights to do
   it.  Without this, a forgotten -d scatters 164 procedures into master. */
IF DB_NAME() <> N'DB02'
BEGIN
    RAISERROR(N'This script expects DB02. Pass -d DB02, or pick DB02 in the database dropdown.', 16, 1);
    SET NOEXEC ON;
END;
GO

PRINT '';
PRINT '#####################################################################';
PRINT '  Maseera — DB02 schema and engine';
PRINT '#####################################################################';
GO

:r 01_config_engine.sql
:r 02_org_and_roster.sql
:r 03_evidence.sql
:r 04_development_framework.sql
:r 05_cycle.sql
:r 06_security.sql
:r 07_evaluation_engine.sql
:r 08_pool_and_open.sql
:r 09_reference_data.sql
:r 10_crud.sql
:r 11_stage.sql
:r 12_idp.sql
:r 13_loads.sql
:r 14_reports.sql

/* =====================================================================================
   The receipt
   ===================================================================================== */
PRINT '';
PRINT '#####################################################################';
PRINT '  Receipt';
PRINT '#####################################################################';
GO

DECLARE @r TABLE (Grp nvarchar(20), ObjectName nvarchar(80), Rows bigint, SortOrder int);

INSERT @r VALUES
 (N'Configuration', N'cfg.Domain',             (SELECT COUNT(*) FROM cfg.Domain),             10),
 (N'Configuration', N'cfg.DomainValue',        (SELECT COUNT(*) FROM cfg.DomainValue),        11),
 (N'Configuration', N'cfg.Operator',           (SELECT COUNT(*) FROM cfg.Operator),           12),
 (N'Configuration', N'cfg.Setting',            (SELECT COUNT(*) FROM cfg.Setting),            13),
 (N'Configuration', N'cfg.Screen',             (SELECT COUNT(*) FROM cfg.Screen),             14),
 (N'Configuration', N'cfg.MenuGroup',          (SELECT COUNT(*) FROM cfg.MenuGroup),          15),
 (N'Configuration', N'cfg.Message',            (SELECT COUNT(*) FROM cfg.Message),            16),
 (N'Reference',     N'sel.RequirementKind',    (SELECT COUNT(*) FROM sel.RequirementKind),    20),
 (N'Reference',     N'sel.EvidenceSource',     (SELECT COUNT(*) FROM sel.EvidenceSource),     21),
 (N'Reference',     N'sel.EvidenceSourceColumn',(SELECT COUNT(*) FROM sel.EvidenceSourceColumn), 22),
 (N'Reference',     N'sel.TableMapping',       (SELECT COUNT(*) FROM sel.TableMapping),       23),
 (N'Reference',     N'sel.MetricDefinition',   (SELECT COUNT(*) FROM sel.MetricDefinition),   24),
 (N'Reference',     N'sel.ProcessType',        (SELECT COUNT(*) FROM sel.ProcessType),        25),
 (N'Reference',     N'sel.StageKind',          (SELECT COUNT(*) FROM sel.StageKind),          26),
 (N'Reference',     N'sel.WizardStep',         (SELECT COUNT(*) FROM sel.WizardStep),         27),
 (N'Reference',     N'sel.CycleRecipe',        (SELECT COUNT(*) FROM sel.CycleRecipe),        28),
 (N'Reference',     N'sel.ValidationRule',     (SELECT COUNT(*) FROM sel.ValidationRule),     29),
 (N'Reference',     N'sel.ReadinessLevel',     (SELECT COUNT(*) FROM sel.ReadinessLevel),     30),
 (N'Reference',     N'sel.MixtureModel',       (SELECT COUNT(*) FROM sel.MixtureModel),       31),
 (N'Reference',     N'sel.StagePerformer',     (SELECT COUNT(*) FROM sel.StagePerformer),     32),
 (N'Reference',     N'sec.Role',               (SELECT COUNT(*) FROM sec.Role),               33),
 (N'Reference',     N'sec.AppUser',            (SELECT COUNT(*) FROM sec.AppUser),            34),
 (N'Reference',     N'sec.RoleScreenGrant',    (SELECT COUNT(*) FROM sec.RoleScreenGrant),    35),
 (N'Business',      N'sel.Employee',           (SELECT COUNT(*) FROM sel.Employee),           50),
 (N'Business',      N'sel.OrgNode',            (SELECT COUNT(*) FROM sel.OrgNode),            51),
 (N'Business',      N'sel.Cycle',              (SELECT COUNT(*) FROM sel.Cycle),              52),
 (N'Business',      N'sel.CycleCandidate',     (SELECT COUNT(*) FROM sel.CycleCandidate),     53),
 (N'Business',      N'sel.CandidateDecision',  (SELECT COUNT(*) FROM sel.CandidateDecision),  54),
 (N'Business',      N'sel.DevEvent',           (SELECT COUNT(*) FROM sel.DevEvent),           55),
 (N'Business',      N'sel.DevFramework',       (SELECT COUNT(*) FROM sel.DevFramework),       56),
 (N'Business',      N'sel.EmployeeRecord',     (SELECT COUNT(*) FROM sel.EmployeeRecord),     57),
 (N'Business',      N'sel.IdpItem',            (SELECT COUNT(*) FROM sel.IdpItem),            58),
 (N'Business',      N'stg.LoadException',      (SELECT COUNT(*) FROM stg.LoadException),      59);

SELECT [Group] = Grp, [Object] = ObjectName, [Rows] = Rows,
       [Check] = CASE WHEN Grp IN (N'Configuration', N'Reference')
                      THEN CASE WHEN Rows > 0 THEN N'ok' ELSE N'EMPTY — expected rows' END
                      ELSE CASE WHEN Rows = 0 THEN N'ok (fresh)' ELSE N'has data' END END
FROM @r ORDER BY SortOrder;

DECLARE @bad int = (SELECT COUNT(*) FROM @r WHERE Grp IN (N'Configuration', N'Reference') AND Rows = 0);
IF @bad > 0
BEGIN
    PRINT '';
    RAISERROR(N'  %d configuration or reference table(s) came back empty. Do not continue.', 16, 1, @bad);
END
ELSE
    PRINT '  Every configuration and reference table has rows.';
GO

PRINT '';
PRINT '#####################################################################';
PRINT '  Done.';
PRINT '#####################################################################';
GO

/* Leave the session usable whether or not the guard at the top fired. */
SET NOEXEC OFF;
GO
