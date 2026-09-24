/* =====================================================================================
   db/dev/01_mock_sources.sql — the customer's operational tables, invented
   -------------------------------------------------------------------------------------
   These are the dbo.* tables sel.TableMapping names.  On the customer's server they are
   fed by their own systems; here they are created and filled so the application can be
   run end to end without them.

   THIS FILE IS FOR DEVELOPMENT ONLY.  It is never part of a deployment: 00_run_all.sql
   does not reference it, and the migration step that runs 01–14 leaves dbo alone.  If
   these tables already exist on a real server, this script must not be run there — it
   drops and refills them.

   There is one database and its name is DB02.  Nothing here reads from anywhere else.
   ===================================================================================== */
/* As in 00_run_all.sql: SSMS and sqlcmd disagree about QUOTED_IDENTIFIER, and this file
   must not depend on which of them is running it. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() <> N'DB02'
BEGIN
    RAISERROR(N'This script expects DB02. There is one database and that is its name.', 16, 1);
    SET NOEXEC ON;
END;
GO

PRINT N'dev/01 — mock source tables';
GO

/* ---- the roster: the wide one, and the only required source --------------------- */
DROP TABLE IF EXISTS dbo.ManpowerPermanent_AllRecords;
CREATE TABLE dbo.ManpowerPermanent_AllRecords
(
    PersonnelNo        nvarchar(30)  NOT NULL PRIMARY KEY,
    EmployeeName       nvarchar(200) NULL,
    OrgCode            nvarchar(40)  NULL,
    OrgName            nvarchar(200) NULL,
    ParentOrgCode      nvarchar(40)  NULL,
    JobTitle           nvarchar(200) NULL,
    PermJobSuffix      nvarchar(30)  NULL,
    PermJobSuffixDesc  nvarchar(200) NULL,
    CurrentJobSuffix   nvarchar(30)  NULL,
    GradeCode          nvarchar(20)  NULL,
    ManagementLevel    nvarchar(40)  NULL,
    ActiveInd          nvarchar(20)  NULL,
    PermChiefInd       nvarchar(10)  NULL,
    HireDate           date          NULL,
    PromotionDate      date          NULL,
    BirthDate          date          NULL,
    Gender             nvarchar(20)  NULL,
    Nationality        nvarchar(60)  NULL,
    SpecialNeedInd     nvarchar(10)  NULL,
    Email              nvarchar(200) NULL,
    /* A handful of the other columns the real record carries, so the roster-field
       screen has something to discover beyond the mapped ones. */
    CostCentre         nvarchar(40)  NULL,
    Location           nvarchar(100) NULL,
    ContractType       nvarchar(40)  NULL,
    LineManagerNo      nvarchar(30)  NULL
);
GO

DROP TABLE IF EXISTS dbo.EmployeeDirectory;
CREATE TABLE dbo.EmployeeDirectory
(
    PersonnelNo nvarchar(30)  NOT NULL PRIMARY KEY,
    LoginName   nvarchar(128) NULL,
    DisplayName nvarchar(200) NULL,
    Email       nvarchar(200) NULL
);
GO

/* ---- evidence: one table per kind, each with its own idea of a status ------------ */
DROP TABLE IF EXISTS dbo.CourseCompletion;
CREATE TABLE dbo.CourseCompletion
(
    CourseCompletionId int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId  nvarchar(30)  NOT NULL,
    CourseId    nvarchar(60)  NOT NULL,
    CourseName  nvarchar(200) NULL,
    [Status]    nvarchar(60)  NULL,
    CompletedOn date          NULL,
    ExpiresOn   date          NULL,
    Provider    nvarchar(100) NULL
);
GO

DROP TABLE IF EXISTS dbo.AssessmentResult;
CREATE TABLE dbo.AssessmentResult
(
    AssessmentResultId int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId   nvarchar(30)  NOT NULL,
    AssessmentId nvarchar(60)  NOT NULL,
    [Status]     nvarchar(60)  NULL,
    Score        decimal(18,4) NULL,
    MaxScore     decimal(18,4) NULL,
    CompletedOn  date          NULL,
    ExpiresOn    date          NULL,
    Centre       nvarchar(100) NULL
);
GO

DROP TABLE IF EXISTS dbo.SurveyResult;
CREATE TABLE dbo.SurveyResult
(
    SurveyResultId int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId  nvarchar(30)  NOT NULL,
    SurveyId    nvarchar(60)  NOT NULL,
    [Status]    nvarchar(60)  NULL,
    Score       decimal(18,4) NULL,
    MaxScore    decimal(18,4) NULL,
    CompletedOn date          NULL,
    Raters      int           NULL
);
GO

/* ---- coverage: the rows the SUM-mode rules add up ------------------------------- */
DROP TABLE IF EXISTS dbo.EmployeeCoverage;
CREATE TABLE dbo.EmployeeCoverage
(
    EmployeeCoverageId int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId     nvarchar(30)  NOT NULL,
    PositionSuffix nvarchar(30)  NOT NULL,
    PositionCode   nvarchar(40)  NULL,
    CoverageType   nvarchar(60)  NULL,
    Department     nvarchar(200) NULL,
    OrgCode        nvarchar(40)  NULL,
    StartDate      date          NULL,
    EndDate        date          NULL,
    Days           decimal(18,4) NULL
);
GO

DROP TABLE IF EXISTS dbo.EmployeePmp;
CREATE TABLE dbo.EmployeePmp
(
    EmployeeId  nvarchar(30)  NOT NULL,
    RatingYear  smallint      NOT NULL,
    RatingCode  nvarchar(20)  NULL,
    RatingValue decimal(18,4) NULL,
    RatingRole  nvarchar(60)  NULL,
    CONSTRAINT PK_dbo_EmployeePmp PRIMARY KEY (EmployeeId, RatingYear)
);
GO

/* ---- succession and positions --------------------------------------------------- */
DROP TABLE IF EXISTS dbo.SuccessionPlan;
CREATE TABLE dbo.SuccessionPlan
(
    SuccessionPlanId int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId nvarchar(30)  NOT NULL,
    Department nvarchar(200) NOT NULL,
    LevelCode  nvarchar(30)  NULL,
    PlanYear   smallint      NULL,
    Remark     nvarchar(400) NULL
);
GO

DROP TABLE IF EXISTS dbo.Position;
CREATE TABLE dbo.Position
(
    PositionCode  nvarchar(40)  NOT NULL PRIMARY KEY,
    PositionName  nvarchar(200) NULL,
    IncumbentId   nvarchar(30)  NULL,
    OrgCode       nvarchar(40)  NULL,
    JobSuffix     nvarchar(30)  NULL,
    IsCritical    bit           NULL
);
GO

DROP TABLE IF EXISTS dbo.PoolMembership;
CREATE TABLE dbo.PoolMembership
(
    PoolMembershipId int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId nvarchar(30) NOT NULL,
    PoolCode   nvarchar(60) NOT NULL,
    PoolYear   smallint     NULL,
    AddedOn    date         NULL
);
GO

/* ---- the four curriculum sources the development track reads -------------------- */
DROP TABLE IF EXISTS dbo.EmployeeJobCertification;
CREATE TABLE dbo.EmployeeJobCertification
(
    Id int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId     nvarchar(30)  NOT NULL,
    CurriculumCode nvarchar(60)  NOT NULL,
    CurriculumName nvarchar(200) NULL,
    [Status]       nvarchar(60)  NULL,
    CompletedOn    date          NULL
);
GO

DROP TABLE IF EXISTS dbo.EmployeeCustomCurriculum;
CREATE TABLE dbo.EmployeeCustomCurriculum
(
    Id int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId     nvarchar(30)  NOT NULL,
    CurriculumCode nvarchar(60)  NOT NULL,
    CurriculumName nvarchar(200) NULL,
    [Status]       nvarchar(60)  NULL,
    CompletedOn    date          NULL
);
GO

DROP TABLE IF EXISTS dbo.EmployeeMandatoryTraining;
CREATE TABLE dbo.EmployeeMandatoryTraining
(
    Id int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId     nvarchar(30)  NOT NULL,
    CurriculumCode nvarchar(60)  NOT NULL,
    CurriculumName nvarchar(200) NULL,
    [Status]       nvarchar(60)  NULL,
    CompletedOn    date          NULL,
    ExpiresOn      date          NULL
);
GO

DROP TABLE IF EXISTS dbo.EmployeeLeadershipProgramme;
CREATE TABLE dbo.EmployeeLeadershipProgramme
(
    Id int IDENTITY(1,1) PRIMARY KEY,
    EmployeeId    nvarchar(30)  NOT NULL,
    ProgrammeCode nvarchar(60)  NOT NULL,
    ProgrammeName nvarchar(200) NULL,
    [Status]      nvarchar(60)  NULL,
    CompletedOn   date          NULL
);
GO

PRINT N'dev/01 — tables created; filling them';
GO

/* =====================================================================================
   The data.  Small enough to load in seconds, shaped like the real thing: a tree eight
   levels deep, a long tail of small units, and evidence that is deliberately uneven so
   the attainment figures are not all the same number.
   ===================================================================================== */

/* ---- the organisation tree ------------------------------------------------------ */
DROP TABLE IF EXISTS #org;
CREATE TABLE #org
(
    OrgCode   nvarchar(40)  NOT NULL PRIMARY KEY,
    OrgName   nvarchar(200) NOT NULL,
    ParentOrgCode nvarchar(40) NULL,
    OrgLevel  int           NOT NULL,
    Headcount int           NOT NULL
);

INSERT #org (OrgCode, OrgName, ParentOrgCode, OrgLevel, Headcount) VALUES
 (N'ORG',        N'The company',                 NULL,          1, 2),
 (N'ORG-UP',     N'Upstream',                    N'ORG',        2, 3),
 (N'ORG-DN',     N'Downstream',                  N'ORG',        2, 3),
 (N'ORG-CORP',   N'Corporate',                   N'ORG',        2, 3),
 (N'UP-EXP',     N'Exploration',                 N'ORG-UP',     3, 4),
 (N'UP-PRD',     N'Production',                  N'ORG-UP',     3, 4),
 (N'DN-REF',     N'Refining',                    N'ORG-DN',     3, 4),
 (N'DN-MKT',     N'Marketing',                   N'ORG-DN',     3, 4),
 (N'CORP-HR',    N'Human resources',             N'ORG-CORP',   3, 4),
 (N'CORP-FIN',   N'Finance',                     N'ORG-CORP',   3, 4),
 (N'EXP-GEO',    N'Geoscience',                  N'UP-EXP',     4, 24),
 (N'EXP-DRL',    N'Drilling',                    N'UP-EXP',     4, 31),
 (N'PRD-ONS',    N'Onshore production',          N'UP-PRD',     4, 46),
 (N'PRD-OFF',    N'Offshore production',         N'UP-PRD',     4, 38),
 (N'PRD-ENG',    N'Production engineering',      N'UP-PRD',     4, 29),
 (N'REF-OPS',    N'Refinery operations',         N'DN-REF',     4, 52),
 (N'REF-MNT',    N'Refinery maintenance',        N'DN-REF',     4, 41),
 (N'MKT-RET',    N'Retail',                      N'DN-MKT',     4, 33),
 (N'MKT-COM',    N'Commercial',                  N'DN-MKT',     4, 22),
 (N'HR-OPS',     N'HR operations',               N'CORP-HR',    4, 18),
 (N'HR-TAL',     N'Talent and development',      N'CORP-HR',    4, 14),
 (N'FIN-CTL',    N'Controlling',                 N'CORP-FIN',   4, 19),
 (N'FIN-TRS',    N'Treasury',                    N'CORP-FIN',   4, 11),
 (N'GEO-SEI',    N'Seismic',                     N'EXP-GEO',    5, 12),
 (N'DRL-WEL',    N'Well services',               N'EXP-DRL',    5, 17),
 (N'ONS-FLD',    N'Field operations',            N'PRD-ONS',    5, 26),
 (N'OFF-PLT',    N'Platform operations',         N'PRD-OFF',    5, 21),
 (N'OPS-CRK',    N'Cracking',                    N'REF-OPS',    5, 24),
 (N'OPS-DST',    N'Distillation',                N'REF-OPS',    5, 23),
 (N'MNT-ROT',    N'Rotating equipment',          N'REF-MNT',    5, 18),
 (N'FLD-N',      N'Northern field',              N'ONS-FLD',    6, 14),
 (N'FLD-S',      N'Southern field',              N'ONS-FLD',    6, 13),
 (N'PLT-A',      N'Platform A',                  N'OFF-PLT',    6, 11),
 (N'CRK-U1',     N'Cracker unit one',            N'OPS-CRK',    6, 12),
 (N'FLDN-SH1',   N'Northern field, shift one',   N'FLD-N',      7, 8),
 (N'PLTA-SH1',   N'Platform A, shift one',       N'PLT-A',      7, 7),
 (N'FLDNSH1-T1', N'Northern field, shift one, team one', N'FLDN-SH1', 8, 5);

/* ---- the people ----------------------------------------------------------------- */
DROP TABLE IF EXISTS #names;
CREATE TABLE #names (n int IDENTITY(1,1) PRIMARY KEY, First nvarchar(60), Last nvarchar(60));
INSERT #names (First, Last) VALUES
 (N'Aisha', N'Al-Rashid'), (N'Bilal', N'Haddad'), (N'Carmen', N'Ortega'), (N'Dmitri', N'Volkov'),
 (N'Elena', N'Marchetti'), (N'Farid', N'Nouri'), (N'Grace', N'Okonkwo'), (N'Hiro', N'Tanaka'),
 (N'Ingrid', N'Larsen'), (N'Jamal', N'Osman'), (N'Kirsten', N'Vogel'), (N'Lucia', N'Ferreira'),
 (N'Mahmoud', N'Saleh'), (N'Nadia', N'Petrova'), (N'Omar', N'Khalil'), (N'Priya', N'Raghavan'),
 (N'Qasim', N'Ahmadi'), (N'Rosa', N'Delgado'), (N'Samir', N'Bakr'), (N'Tara', N'Lindqvist'),
 (N'Usman', N'Iqbal'), (N'Vera', N'Novak'), (N'Wei', N'Zhang'), (N'Xenia', N'Papadaki'),
 (N'Yusuf', N'Demir'), (N'Zara', N'Mansour'), (N'Adam', N'Brennan'), (N'Beatrice', N'Laurent'),
 (N'Caleb', N'Mwangi'), (N'Dalia', N'Haddad'), (N'Ewan', N'MacLeod'), (N'Fatima', N'Zaidi'),
 (N'Gustav', N'Holm'), (N'Hana', N'Kovac'), (N'Idris', N'Bello'), (N'Julia', N'Sorensen'),
 (N'Karim', N'Tahir'), (N'Leila', N'Nasser'), (N'Marcus', N'Whitfield'), (N'Nour', N'Barakat');

DROP TABLE IF EXISTS #suffix;
CREATE TABLE #suffix (Rn int NOT NULL PRIMARY KEY, Suffix nvarchar(30) NOT NULL UNIQUE, Descr nvarchar(200), JobTitle nvarchar(200), Grade nvarchar(20), MgmtLevel nvarchar(40));
INSERT #suffix (Rn, Suffix, Descr, JobTitle, Grade, MgmtLevel) VALUES
 (1, N'ENG1', N'Engineer, first level',      N'Engineer',                    N'G09', N'PROFESSIONAL'),
 (2, N'ENG2', N'Engineer, senior',           N'Senior engineer',             N'G11', N'PROFESSIONAL'),
 (3, N'SUP1', N'Supervisor',                 N'Supervisor',                  N'G12', N'SUPERVISOR'),
 (4, N'SUP2', N'Senior supervisor',          N'Senior supervisor',           N'G13', N'SUPERVISOR'),
 (5, N'MGR1', N'Manager, unit',              N'Unit manager',                N'G14', N'MANAGER'),
 (6, N'MGR2', N'Manager, department',        N'Department manager',          N'G15', N'MANAGER'),
 (7, N'DIR1', N'Director',                   N'Director',                    N'G16', N'DIRECTOR'),
 (8, N'ANA1', N'Analyst',                    N'Analyst',                     N'G08', N'PROFESSIONAL'),
 (9, N'ANA2', N'Analyst, senior',            N'Senior analyst',              N'G10', N'PROFESSIONAL'),
 (10, N'TEC1', N'Technician',                 N'Technician',                  N'G06', N'TECHNICAL');

DECLARE @today date = CAST(SYSUTCDATETIME() AS date);

;WITH numbers AS
(
    SELECT TOP (900) n = ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
leaves AS
(
    /* Every unit holds at least a couple of people, because sel.OrgNode is learned from
       the roster and nothing else: a unit nobody is in is a unit the tree never hears
       about, and a grant on it would then match nothing. The branches are thin and the
       leaves are thick, which is the shape of the real thing. */
    SELECT o.OrgCode, o.OrgName, o.ParentOrgCode, o.Headcount,
           StartAt = SUM(o.Headcount) OVER (ORDER BY o.OrgCode ROWS UNBOUNDED PRECEDING) - o.Headcount
    FROM #org o WHERE o.Headcount > 0
),
placed AS
(
    SELECT n.n, l.OrgCode, l.OrgName, l.ParentOrgCode
    FROM numbers n
    JOIN leaves l ON n.n > l.StartAt AND n.n <= l.StartAt + l.Headcount
)
INSERT dbo.ManpowerPermanent_AllRecords
(
    PersonnelNo, EmployeeName, OrgCode, OrgName, ParentOrgCode, JobTitle,
    PermJobSuffix, PermJobSuffixDesc, CurrentJobSuffix, GradeCode, ManagementLevel,
    ActiveInd, PermChiefInd, HireDate, PromotionDate, BirthDate, Gender, Nationality,
    SpecialNeedInd, Email, CostCentre, Location, ContractType, LineManagerNo
)
SELECT
    PersonnelNo = N'E' + RIGHT(N'00000' + CONVERT(nvarchar(10), 10000 + p.n), 5),
    EmployeeName = nm.First + N' ' + nm.Last,
    p.OrgCode, p.OrgName, p.ParentOrgCode,
    sx.JobTitle,
    PermJobSuffix = sx.Suffix,
    PermJobSuffixDesc = sx.Descr,
    /* One in nine is acting in something other than their own suffix. */
    CurrentJobSuffix = CASE WHEN p.n % 9 = 0 THEN up.Suffix ELSE sx.Suffix END,
    sx.Grade, sx.MgmtLevel,
    ActiveInd = CASE WHEN p.n % 47 = 0 THEN N'N' ELSE N'Y' END,
    PermChiefInd = CASE WHEN sx.Suffix IN (N'DIR1', N'MGR2') THEN N'Y' ELSE N'N' END,
    HireDate = DATEADD(DAY, -(400 + (p.n * 37) % 8000), @today),
    PromotionDate = DATEADD(DAY, -(60 + (p.n * 53) % 2600), @today),
    BirthDate = DATEADD(DAY, -(8000 + (p.n * 61) % 9000), @today),
    Gender = CASE WHEN p.n % 3 = 0 THEN N'F' ELSE N'M' END,
    Nationality = CASE p.n % 5 WHEN 0 THEN N'National' WHEN 1 THEN N'National'
                               WHEN 2 THEN N'National' WHEN 3 THEN N'Expatriate' ELSE N'National' END,
    SpecialNeedInd = CASE WHEN p.n % 83 = 0 THEN N'Y' ELSE N'N' END,
    Email = LOWER(REPLACE(nm.First, N'''', N'') + N'.' + REPLACE(nm.Last, N'-', N'') ) + N'@example.test',
    CostCentre = N'CC' + RIGHT(N'0000' + CONVERT(nvarchar(10), 1000 + (p.n % 40)), 4),
    Location = CASE p.n % 4 WHEN 0 THEN N'Head office' WHEN 1 THEN N'Northern site'
                            WHEN 2 THEN N'Southern site' ELSE N'Offshore' END,
    ContractType = CASE WHEN p.n % 31 = 0 THEN N'Fixed term' ELSE N'Permanent' END,
    LineManagerNo = NULL
FROM placed p
JOIN #suffix sx ON sx.Rn = (p.n % 10) + 1
JOIN #suffix up ON up.Rn = ((p.n + 3) % 10) + 1
/* A stride that is coprime with the table size, so names vary within a unit instead
   of marching in step with the org placement. */
JOIN #names nm ON nm.n = ((p.n * 17) % 40) + 1;

DECLARE @n_manpowerpermanent_allrecords int = (SELECT COUNT(*) FROM dbo.ManpowerPermanent_AllRecords);
PRINT N'  roster                    ' + CONVERT(nvarchar(10), @n_manpowerpermanent_allrecords);
GO

/* Line managers: the first person in the parent unit, where there is one. */
UPDATE r
SET LineManagerNo = m.PersonnelNo
FROM dbo.ManpowerPermanent_AllRecords r
OUTER APPLY (SELECT TOP (1) p.PersonnelNo
             FROM dbo.ManpowerPermanent_AllRecords p
             WHERE p.OrgCode = r.ParentOrgCode
             ORDER BY p.GradeCode DESC, p.PersonnelNo) m
WHERE m.PersonnelNo IS NOT NULL;
GO

/* ---- the directory, for owner and delegate search ------------------------------- */
INSERT dbo.EmployeeDirectory (PersonnelNo, LoginName, DisplayName, Email)
SELECT PersonnelNo,
       LoginName = N'maseera.' + LOWER(REPLACE(PersonnelNo, N'E', N'u')),
       EmployeeName, Email
FROM dbo.ManpowerPermanent_AllRecords;
GO

/* ---- performance, three years of it --------------------------------------------- */
DECLARE @thisYear smallint = CAST(YEAR(SYSUTCDATETIME()) AS smallint);

INSERT dbo.EmployeePmp (EmployeeId, RatingYear, RatingCode, RatingValue, RatingRole)
SELECT r.PersonnelNo, y.RatingYear,
       RatingCode = CASE (ABS(CHECKSUM(r.PersonnelNo, y.RatingYear)) % 10)
                        WHEN 0 THEN N'A' WHEN 1 THEN N'A' WHEN 2 THEN N'B+'
                        WHEN 3 THEN N'B' WHEN 4 THEN N'B' WHEN 5 THEN N'B'
                        WHEN 6 THEN N'B-' WHEN 7 THEN N'C' WHEN 8 THEN N'C' ELSE N'D' END,
       RatingValue = 40 + (ABS(CHECKSUM(r.PersonnelNo, y.RatingYear)) % 60),
       RatingRole = N'Line manager'
FROM dbo.ManpowerPermanent_AllRecords r
CROSS JOIN (VALUES (@thisYear - 1), (@thisYear - 2), (@thisYear - 3)) y (RatingYear)
WHERE ABS(CHECKSUM(r.PersonnelNo, y.RatingYear)) % 20 > 0;   /* a few have no rating that year */
GO

/* ---- courses: some finished, some in progress, some expired --------------------- */
DECLARE @today date = CAST(SYSUTCDATETIME() AS date);

DROP TABLE IF EXISTS #courses;
CREATE TABLE #courses (CourseId nvarchar(60) PRIMARY KEY, CourseName nvarchar(200), ValidMonths int NULL, Likelihood int);
INSERT #courses VALUES
 (N'CRS-SAFE-01',  N'Process safety, foundation',        24, 9),
 (N'CRS-SAFE-02',  N'Process safety, advanced',          24, 5),
 (N'CRS-LEAD-01',  N'Leading a team',                  NULL, 6),
 (N'CRS-LEAD-02',  N'Leading leaders',                 NULL, 3),
 (N'CRS-LEAD-02B', N'Leading leaders (the old code)',  NULL, 2),
 (N'CRS-FIN-01',   N'Finance for non-financial people',NULL, 5),
 (N'CRS-CAP-02',   N'Capital project appraisal',       NULL, 4),
 (N'CRS-HSE-01',   N'Health, safety and environment',    12, 9),
 (N'CRS-DIG-01',   N'Digital foundations',             NULL, 7);

INSERT dbo.CourseCompletion (EmployeeId, CourseId, CourseName, [Status], CompletedOn, ExpiresOn, Provider)
SELECT r.PersonnelNo, c.CourseId, c.CourseName,
       [Status] = CASE WHEN ABS(CHECKSUM(r.PersonnelNo, c.CourseId)) % 11 = 0 THEN N'In progress' ELSE N'Completed' END,
       CompletedOn = done.d,
       /* An expiry that has passed is not a completion, and the engine has to see it. */
       ExpiresOn = CASE WHEN c.ValidMonths IS NULL THEN NULL ELSE DATEADD(MONTH, c.ValidMonths, done.d) END,
       Provider = N'Corporate academy'
FROM dbo.ManpowerPermanent_AllRecords r
JOIN #courses c ON ABS(CHECKSUM(r.PersonnelNo, c.CourseId)) % 10 < c.Likelihood
CROSS APPLY (SELECT d = DATEADD(DAY, -(30 + ABS(CHECKSUM(r.PersonnelNo, c.CourseId)) % 1400), @today)) done;

DECLARE @n_coursecompletion int = (SELECT COUNT(*) FROM dbo.CourseCompletion);
PRINT N'  course completions        ' + CONVERT(nvarchar(10), @n_coursecompletion);
GO

/* ---- assessments, with a real score against a maximum --------------------------- */
DECLARE @today date = CAST(SYSUTCDATETIME() AS date);

INSERT dbo.AssessmentResult (EmployeeId, AssessmentId, [Status], Score, MaxScore, CompletedOn, ExpiresOn, Centre)
SELECT r.PersonnelNo, a.AssessmentId,
       [Status] = CASE WHEN sc.Score >= 60 THEN N'Completed' ELSE N'Attempted' END,
       sc.Score, MaxScore = 100,
       CompletedOn = DATEADD(DAY, -(20 + ABS(CHECKSUM(r.PersonnelNo, a.AssessmentId)) % 900), @today),
       ExpiresOn = NULL,
       Centre = N'Assessment centre'
FROM dbo.ManpowerPermanent_AllRecords r
CROSS JOIN (VALUES (N'ASM-360-01'), (N'ASM-360-02'), (N'ASM-COG-01'), (N'ASM-LEAD-01')) a (AssessmentId)
CROSS APPLY (SELECT Score = CAST(35 + (ABS(CHECKSUM(r.PersonnelNo, a.AssessmentId)) % 65) AS decimal(18,4))) sc
WHERE ABS(CHECKSUM(r.PersonnelNo, a.AssessmentId)) % 10 < 6;

INSERT dbo.SurveyResult (EmployeeId, SurveyId, [Status], Score, MaxScore, CompletedOn, Raters)
SELECT r.PersonnelNo, N'SVY-360-01', N'Completed',
       Score = CAST(45 + (ABS(CHECKSUM(r.PersonnelNo, N'SVY')) % 55) AS decimal(18,4)), 100,
       DATEADD(DAY, -(40 + ABS(CHECKSUM(r.PersonnelNo, N'SVY')) % 700), @today),
       Raters = 6 + (ABS(CHECKSUM(r.PersonnelNo, N'R')) % 8)
FROM dbo.ManpowerPermanent_AllRecords r
WHERE ABS(CHECKSUM(r.PersonnelNo, N'SVY')) % 10 < 4;
GO

/* ---- coverage: the acting spells the SUM rules add up --------------------------- */
DECLARE @today date = CAST(SYSUTCDATETIME() AS date);

/* Everyone's substantive assignment. */
INSERT dbo.EmployeeCoverage
    (EmployeeId, PositionSuffix, PositionCode, CoverageType, Department, OrgCode, StartDate, EndDate, Days)
SELECT r.PersonnelNo, r.PermJobSuffix, N'POS-' + r.OrgCode + N'-' + r.PermJobSuffix,
       N'PERMANENT', r.OrgName, r.OrgCode, r.PromotionDate, NULL,
       DATEDIFF(DAY, r.PromotionDate, @today)
FROM dbo.ManpowerPermanent_AllRecords r
WHERE r.PromotionDate IS NOT NULL;

/* Acting spells, unevenly spread, in departments that are not always their own. */
INSERT dbo.EmployeeCoverage
    (EmployeeId, PositionSuffix, PositionCode, CoverageType, Department, OrgCode, StartDate, EndDate, Days)
SELECT r.PersonnelNo,
       PositionSuffix = CASE s.spell % 3 WHEN 0 THEN N'MGR1' WHEN 1 THEN N'DIR1' ELSE N'SUP2' END,
       PositionCode = N'POS-ACT-' + CONVERT(nvarchar(10), s.spell),
       /* The type does not follow the suffix: deriving both from the same spell number
          would make every director spell temporary and every manager spell acting, and
          a rule that filters on the type would then read as broken rather than strict. */
       CoverageType = CASE WHEN ABS(CHECKSUM(r.PersonnelNo, s.spell, N'type')) % 3 = 0
                           THEN N'TEMPORARY' ELSE N'ACTING' END,
       Department = o.OrgName, OrgCode = o.OrgCode,
       StartDate = st.d,
       EndDate = DATEADD(DAY, 20 + (ABS(CHECKSUM(r.PersonnelNo, s.spell)) % 200), st.d),
       Days = 21 + (ABS(CHECKSUM(r.PersonnelNo, s.spell)) % 200)
FROM dbo.ManpowerPermanent_AllRecords r
CROSS JOIN (VALUES (1), (2), (3)) s (spell)
CROSS APPLY (SELECT d = DATEADD(DAY, -(90 + (ABS(CHECKSUM(r.PersonnelNo, s.spell)) % 2000)), @today)) st
CROSS APPLY (SELECT TOP (1) OrgCode, OrgName FROM #org
             WHERE Headcount > 0 ORDER BY ABS(CHECKSUM(r.PersonnelNo, s.spell, OrgCode))) o
WHERE ABS(CHECKSUM(r.PersonnelNo, s.spell)) % 10 < 5;

DECLARE @n_employeecoverage int = (SELECT COUNT(*) FROM dbo.EmployeeCoverage);
PRINT N'  coverage rows             ' + CONVERT(nvarchar(10), @n_employeecoverage);
GO

/* ---- last year's succession plan, positions and pool ---------------------------- */
DECLARE @thisYear smallint = CAST(YEAR(SYSUTCDATETIME()) AS smallint);

INSERT dbo.SuccessionPlan (EmployeeId, Department, LevelCode, PlanYear, Remark)
SELECT TOP (60) r.PersonnelNo, r.OrgName,
       LevelCode = CASE (ABS(CHECKSUM(r.PersonnelNo)) % 4)
                       WHEN 0 THEN N'READY_NOW' WHEN 1 THEN N'ONE_TO_TWO'
                       WHEN 2 THEN N'THREE_TO_FIVE' ELSE N'LONGER' END,
       PlanYear = @thisYear - 1,
       Remark = N'Carried from last year''s plan.'
FROM dbo.ManpowerPermanent_AllRecords r
WHERE r.ManagementLevel IN (N'SUPERVISOR', N'MANAGER')
ORDER BY r.PersonnelNo;

/* One position per organisation and suffix, with the longest-serving of the people who
   hold it named as the incumbent. A position with two incumbents is a data error, not a
   thing to average over. */
INSERT dbo.Position (PositionCode, PositionName, IncumbentId, OrgCode, JobSuffix, IsCritical)
SELECT TOP (40) z.PositionCode, z.PositionName, z.IncumbentId, z.OrgCode, z.PermJobSuffix, z.IsCritical
FROM (
    SELECT PositionCode = N'POS-' + r.OrgCode + N'-' + r.PermJobSuffix,
           PositionName = r.JobTitle + N', ' + r.OrgName,
           IncumbentId = r.PersonnelNo, r.OrgCode, r.PermJobSuffix,
           IsCritical = CASE WHEN r.ManagementLevel IN (N'DIRECTOR', N'MANAGER') THEN 1 ELSE 0 END,
           rn = ROW_NUMBER() OVER (PARTITION BY r.OrgCode, r.PermJobSuffix ORDER BY r.HireDate, r.PersonnelNo)
    FROM dbo.ManpowerPermanent_AllRecords r
    WHERE r.ManagementLevel IN (N'DIRECTOR', N'MANAGER', N'SUPERVISOR')
) z
WHERE z.rn = 1
ORDER BY z.PositionCode;

INSERT dbo.PoolMembership (EmployeeId, PoolCode, PoolYear, AddedOn)
SELECT TOP (80) r.PersonnelNo, N'TALENT', @thisYear - 1,
       DATEADD(YEAR, -1, CAST(SYSUTCDATETIME() AS date))
FROM dbo.ManpowerPermanent_AllRecords r
WHERE r.ManagementLevel IN (N'PROFESSIONAL', N'SUPERVISOR')
ORDER BY NEWID();
GO

/* ---- curricula ------------------------------------------------------------------ */
DECLARE @today date = CAST(SYSUTCDATETIME() AS date);

INSERT dbo.EmployeeMandatoryTraining (EmployeeId, CurriculumCode, CurriculumName, [Status], CompletedOn, ExpiresOn)
SELECT r.PersonnelNo, m.Code, m.Name,
       CASE WHEN ABS(CHECKSUM(r.PersonnelNo, m.Code)) % 7 = 0 THEN N'Overdue' ELSE N'Completed' END,
       DATEADD(DAY, -(10 + ABS(CHECKSUM(r.PersonnelNo, m.Code)) % 500), @today),
       DATEADD(DAY,  350 - (ABS(CHECKSUM(r.PersonnelNo, m.Code)) % 500), @today)
FROM dbo.ManpowerPermanent_AllRecords r
CROSS JOIN (VALUES (N'MND-HSE-01', N'Annual safety refresher'),
                   (N'MND-ETH-01', N'Code of conduct')) m (Code, Name);

INSERT dbo.EmployeeJobCertification (EmployeeId, CurriculumCode, CurriculumName, [Status], CompletedOn)
SELECT r.PersonnelNo, N'JC-' + r.PermJobSuffix, N'Job certification, ' + r.PermJobSuffixDesc,
       CASE WHEN ABS(CHECKSUM(r.PersonnelNo, N'JC')) % 3 = 0 THEN N'In progress' ELSE N'Completed' END,
       DATEADD(DAY, -(30 + ABS(CHECKSUM(r.PersonnelNo, N'JC')) % 900), @today)
FROM dbo.ManpowerPermanent_AllRecords r;

INSERT dbo.EmployeeLeadershipProgramme (EmployeeId, ProgrammeCode, ProgrammeName, [Status], CompletedOn)
SELECT r.PersonnelNo, N'LP-CORE', N'Core leadership programme',
       CASE WHEN ABS(CHECKSUM(r.PersonnelNo, N'LP')) % 4 = 0 THEN N'Completed' ELSE N'Nominated' END,
       DATEADD(DAY, -(60 + ABS(CHECKSUM(r.PersonnelNo, N'LP')) % 700), @today)
FROM dbo.ManpowerPermanent_AllRecords r
WHERE r.ManagementLevel IN (N'SUPERVISOR', N'MANAGER', N'DIRECTOR');

INSERT dbo.EmployeeCustomCurriculum (EmployeeId, CurriculumCode, CurriculumName, [Status], CompletedOn)
SELECT TOP (120) r.PersonnelNo, N'CC-DIGITAL', N'Digital upskilling', N'In progress', NULL
FROM dbo.ManpowerPermanent_AllRecords r ORDER BY NEWID();
GO

/* ---- two rows the loads deliberately cannot place -------------------------------
   A personnel number the roster does not carry. The load sets it aside with a sentence
   rather than dropping it, and the answer is an alias — never a fuzzy match on a name. */
INSERT dbo.CourseCompletion (EmployeeId, CourseId, CourseName, [Status], CompletedOn, Provider)
VALUES (N'LEGACY-7741', N'CRS-SAFE-01', N'Process safety, foundation', N'Completed',
        DATEADD(DAY, -200, CAST(SYSUTCDATETIME() AS date)), N'Legacy system'),
       (N'LEGACY-7742', N'CRS-LEAD-01', N'Leading a team', N'Completed',
        DATEADD(DAY, -320, CAST(SYSUTCDATETIME() AS date)), N'Legacy system');
GO

PRINT N'dev/01 — source data in place';
GO

/* Leave the session usable whether or not the DB02 guard at the top fired. */
SET NOEXEC OFF;
GO
