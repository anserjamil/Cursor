# The screens

Every screen is a row in `cfg.Screen`, and access to it is a row in `sec.RoleScreenGrant`
or `sec.UserScreenGrant`. Adding a screen is a migration and a controller, never a change
to the navigation markup: `cfg.usp_Menu` builds the menu from these rows and filters it
through `sec.fn_ScreenAccess`, so a screen the viewer cannot read never appears at all.

The screens that are **not in a menu** are reached from the thing they belong to — a
stage from its cycle, a profile from a list, health from the account menu. They are still
registered, still granted, and still in the jump-to-anything palette.

## In the menu

| Screen code | Name | Area / controller | Menu group |
|---|---|---|---|
| `/Selection/Cycles/` | Cycles | Selection / Cycles | Succession |
| `/Selection/Employees/` | Employee roster | Selection / Employees | Succession |
| `/Selection/CycleSetup/` | Cycle design | Selection / CycleSetup | Configuration |
| `/Selection/Setup/` | Development framework | Config / DevFramework | Configuration |
| `/Config/RosterFields/` | Roster fields | Config / RosterFields | Configuration |
| `/Config/TableMapping/` | Table mapping | Config / TableMapping | Configuration |
| `/Config/RefData/` | Reference data | Config / RefData | Configuration |
| `/Selection/Reports/` | Reports | Selection / Reports | Reports |
| `/Selection/Audit/` | Decision log | Selection / Audit | Reports |
| `/Admin/Policy/` | Access control | Admin / Policy | Access |
| `/Admin/Rls/` | Row-level security | Admin / Rls | Access |
| `/Admin/LoadExceptions/` | Load exceptions | Admin / LoadExceptions | Access |

## Reached from something else

| Screen code | Name | Area / controller | Reached from |
|---|---|---|---|
| `/Selection/Identify/` | Identify | Selection / Identify | a talent-review cycle |
| `/Selection/Review/` | Review | Selection / Review | a talent-review cycle |
| `/Selection/Calibrate/` | Calibration | Selection / Calibrate | a talent-review cycle |
| `/Selection/SuccessionIdentify/` | Succession identify | Selection / SuccessionIdentify | a succession cycle |
| `/Selection/SuccessionReview/` | Succession review | Selection / SuccessionReview | a succession cycle |
| `/Selection/SuccessionCalibrate/` | Succession calibration | Selection / SuccessionCalibrate | a succession cycle |
| `/Selection/Develop/` | Development | Selection / Develop | a development cycle |
| `/Selection/Compare/` | Compare | Selection / Compare | any list of people |
| `/Selection/Profile/` | Profile | Selection / Profile | any person, anywhere |
| `/Admin/Health/` | Health | Admin / Health | the account menu |

> `/Selection/Setup/` is the development framework. The code says Selection because that
> is the screen the business calls "setup"; the controller lives in the Config area
> because that is what it configures. The registry is what reconciles the two, which is
> the point of having one.

---

## What each screen is for

### Cycles
The cycles you can see and what each is waiting on. Every figure is counted inside the
organisations you have been granted, so two people looking at the same cycle will not see
the same numbers — that is the scope working, and the hero band says so.

One primary action per card, into the stage the cycle is actually waiting on.

### Cycle design
The wizard. Six steps from `sel.WizardStep`, with a progress meter that reads
*"3 of 5 set · 1 skipped · still to do: Eligible pool."* A step can be skipped; a blocking
validation cannot. Opening is the irreversible act, and it is the moment the pool snapshot
is written.

The pool preview distinguishes **nobody qualifies** from **the question could not be
asked**: the first is a count of zero, the second is a null count with a sentence. The
screen never renders the second as a zero.

### Identify · Review · Calibration
Three faces of one stage, served by one procedure (`sel.usp_Stage_Candidates`) so they
cannot drift. The funnel boxes come from `sel.fn_CandidateBox`; the pills are rows in
`sel.FunnelPill`, with their own captions, tooltips, groups, semantic roles and whether
they count to the total.

A decision is never overwritten — a change is a new row in `sel.CandidateDecision`.

### Succession identify · review · calibration
The same three shapes over plans and positions rather than a pool. A plan check reads the
framework requirement against the plan-specific rule and shows **where the days were
actually served**, because the framework answer and the plan answer can legitimately
differ and both are worth seeing.

### Development and the individual development plan
Unmet requirements turned into booked, dated plans.

- "Plan created" means every open requirement has a booking, a pencilled date, or coverage
  days. Approval is plan-level, not per requirement.
- Coverage is never auto-assigned. Somebody decides it.
- Two requirements can share a name across sources; the item code is printed beside the
  name so they are never confused.
- A person who completes stays on screen. Nothing re-sorts under the cursor.
- The target date is the stage window's start plus `(levelIndex + 1) × 6` months, and it
  is overridable.
- A course is booked onto a **session**, which has seats, not onto a date.
- Outside the stage window the screen is read-only unless test mode is on.

### Profile
The reason this screen exists is the **readiness ladder**. Each rung says what it asks,
how far along the person is against the threshold tick, and whether they hold it, are
short by so much, or are disqualified. A must not met disqualifies outright, whatever the
percentage says, and the screen says that in words rather than leaving it to be inferred.

Every requirement carries its reason — *"99 against 75 via ASM-360-02"* — met or not.

### Compare
Up to `COMPARE_MAX` people side by side, each column removable.

### Employee roster
The mapped roster, paged on the server. Sensitive columns are readable on a person's
record and **refused as a filter**, and the refusal names the column and says why.

### Reports
Driven by `sel.ReportDefinition`: a new report is a row and a procedure, not a new page.
A `share` column is returned as a count and a total and formatted by the one helper, so a
figure can never contradict the number beside it. Every report says what it counted and
against what.

### Decision log
Every decision, filterable by word, with the chips counted from the data. Anything taken
in test mode is stamped `TEST` and stays stamped.

### Development framework
Events, frameworks, the mixture model and the sources. An event is a question; the rule
under it is how the question gets answered from the data. The rule sentence is rendered by
`sel.fn_EventRuleShort` — never composed in C# — so a list and its rule cannot drift apart.

An equivalence is read with **its own** rule and **its own** source, which is what lets an
older course code still count.

### Roster fields
Every column on the employee record, discovered switched off. **Enabled** means usable as
a criterion; **sensitive** means readable on a record and refused as a filter. They are
different questions, and a sensitive field is never enabled.

### Table mapping
Every table the application reads, what reads it, and what breaks when it is not mapped.
A missing source is never a silent zero.

### Reference data
The lists the whole application reads from. Rename a value and it is renamed everywhere,
including on decisions already taken. A system list refuses deletion of a code something
depends on, and the refusal names what.

### Access control
The grant matrix, and the six rules rendered as a numbered list. "No rule" is a visible
fourth state, not an empty cell. `AUDITOR` carries `IsReadOnly`, and no grant can give it
write.

### Row-level security
The organisation tree with granted / not granted, and a comparison of two viewers' scopes.
Two people looking at the same cycle legitimately see different numbers; this is where
that stops being surprising.

### Load exceptions
Rows the loads could not place, set aside rather than dropped. The answer to a mismatched
personnel number is an alias — never a fuzzy match on a name.

### Health
The startup self-check, on demand, plus recent configuration changes. The health endpoint
calls a procedure like everything else: there is no SQL text in the application, not even
a `SELECT 1`.
