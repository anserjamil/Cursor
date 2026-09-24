# What the application reads, and what breaks when it cannot

There is one database and its name is **DB02**. Nothing here reads, references or migrates
anything from anywhere else.

Every table the application touches is a row in `sel.TableMapping`. Nothing is hardcoded:
a customer whose roster is called something different changes a row, presses **Save and
re-read**, and the mapping is checked against the database rather than assumed. The column
list under each row on the Table mapping screen is what was actually found.

`IsMapped` is set by discovery (`sel.usp_TableMapping_Discover`), never by hand.

## The tables

| Source | Table | Person column | Item column | Read by | What breaks without it |
|---|---|---|---|---|---|
| `ROSTER` **(required)** | `dbo.ManpowerPermanent_AllRecords` | `PersonnelNo` | — | every candidate, criterion and list | No pool can be resolved; the application has nobody to show. |
| `DIRECTORY` | `dbo.EmployeeDirectory` | `PersonnelNo` | — | owner and delegate search | No delegate can be named. |
| `PLAN` | `dbo.SuccessionPlan` | `EmployeeId` | `Department` | succession identify and review | Every candidate looks new — no history. |
| `POSITION` | `dbo.Position` | `IncumbentId` | `PositionCode` | by-position view and incumbent advisory | No positions, and no successors named. |
| `POOL` | `dbo.PoolMembership` | `EmployeeId` | `PoolCode` | existing-pool carry-in | Last year's pool cannot be carried. |
| `COURSE` | `dbo.CourseCompletion` | `EmployeeId` | `CourseId` | `COURSE` evidence | Course requirements can never be met. |
| `ASSESSMENT` | `dbo.AssessmentResult` | `EmployeeId` | `AssessmentId` | `ASSESSMENT` evidence | Assessment requirements can never be met. |
| `FEEDBACK360` | `dbo.SurveyResult` | `EmployeeId` | `SurveyId` | 360 evidence | 360 requirements can never be met. |
| `EXPERIENCE` | `dbo.EmployeeCoverage` | `EmployeeId` | `PositionSuffix` | coverage days | Acting and coverage requirements can never be met. |
| `JOBCERT` | `dbo.EmployeeJobCertification` | `EmployeeId` | `CurriculumCode` | development identify | No curriculum to propose. |
| `CUSTOMCUR` | `dbo.EmployeeCustomCurriculum` | `EmployeeId` | `CurriculumCode` | development identify | Custom curricula are invisible. |
| `MANDTRAIN` | `dbo.EmployeeMandatoryTraining` | `EmployeeId` | `CurriculumCode` | development identify | Mandatory training is invisible. |
| `LEADPROG` | `dbo.EmployeeLeadershipProgramme` | `EmployeeId` | `ProgrammeCode` | development identify | Leadership programmes are invisible. |
| `PMP` | `dbo.EmployeePmp` | `EmployeeId` | — | profile and the three-year average | No performance history is shown. |

Only `ROSTER` is required. Everything else degrades to a stated absence rather than to a
quiet zero: an unmapped source shows **"No table is mapped for this kind, so every
requirement that names it can never be met"** on the requirement itself, on the source, and
on the framework that uses it.

## The ~200-column employee record

`sel.Employee` deliberately holds only the handful of columns the engine itself joins on.
The wide record stays where it is, in the mapped roster table, and is reached two ways:

- **`sel.RosterField`** — what a criterion may name. Every column is discovered switched
  off; an administrator enables the ones that are meaningful, and marks the ones that are
  sensitive.
- **`sel.ColumnCatalog`** — what the column picker on a stage table may show.
  `sel.usp_Stage_Candidates` builds its SELECT list from this and validates every name
  against it, which is how a runtime-chosen column list stays safe.

A new roster column therefore needs **no migration**: run *Re-read the columns*, and it
appears switched off, waiting to be enabled.

### Sensitive columns

`ROSTER_COL_*` settings name the roster's own columns; `SENSITIVE_COLUMNS` names the ones
that are sensitive by default. Gender, nationality, birth dates and the special-need
indicator are:

- **readable** on a person's record, and
- **refused as a filter**, with a sentence that says which column and why.

A sensitive field is never enabled as a criterion. `sel.usp_RosterField_Save` enforces
that: marking a field sensitive switches it off as a criterion in the same statement, so
the two can never disagree.

## Personnel numbers that do not match

Sources use their own identifiers. When a row's key is not a personnel number in the
roster, the load sets the row aside in `stg.LoadException` with a sentence rather than
dropping it. The answer is a row in `sel.PersonAlias` — an exact statement that this key is
that person.

**Never a fuzzy match on a name.** Two people called the same thing is not a rare case in
a company of 79,000.

An alias changes nothing until the next sync, which is when the rows it unlocks are read
and the exception it answered is closed.

## Evidence

`sel.EvidenceSource` says, per requirement kind, which table the engine reads, which
column holds the item, which holds the status, what value counts as a pass, and which
column holds the measure. The join is stated back as a sentence built from the live
values, so the sentence cannot describe a join the engine will not run.

`sel.EvidenceSourceColumn` is the field list a condition may name. A field typed by an
author is **learned** into it and offered to everyone after, so the next author picks from
a list instead of guessing a spelling. A column that is named but not present on the table
is flagged rather than silently failing — and a condition on it fails **its own** condition
only, never the whole rule.

## Metrics

Some criteria are figures rather than columns: coverage days, the three-year performance
average, courses completed, director acting days, tenure. They live in
`sel.MetricDefinition` and `sel.EmployeeMetric`, appear in `sel.RosterField` with
`SourceKind = 'METRIC'`, and are rebuilt by `sel.usp_Metric_Refresh`.

The rows behind an aggregate are kept as well as the aggregate. An aggregate cannot be
taken apart again, which is why `sel.EmployeeCoverage` holds the spells and
`sel.EmployeeMetric` holds the total: the criteria need the total, and the SUM-mode rules
need the spells so their conditions can decide which ones count.

## The development-only fixture

`db/dev/` creates the `dbo.*` tables above and fills them, then loads and configures
everything **through the same procedures the screens call**. It is not part of a
deployment: `db/00_run_all.sql` does not reference it, and it refuses to run against
anything not called DB02.

If those tables already exist on a real server, do not run it there — it drops and refills
them.
