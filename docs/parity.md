# The engine, pinned

## What this document is, and what it is not

Part 13 of the build prompt asks for an engine parity fixture: a set of people whose
answers are compared against the prototype's, so the two cannot drift.

**The prototype does not exist in this repository.** `Maseera.dc.html`, the `db02/00`–`09`
documents and the handoff notes that Part 0 treats as given are not present, and no copy
of them was found anywhere on this machine. The schema, the reference data and the engine
were reconstructed from the Part 3.2 object inventory plus the behavioural descriptions in
Parts 8 and 9.

So parity **against the prototype has not been established, and cannot be from here.**
Anyone who has those documents should run the comparison before this goes near a real
cycle.

What this document does instead is pin the engine's behaviour to a fixture that exists, so
that a change to the engine that alters an answer is visible in a diff rather than in a
calibration meeting. Every figure below comes from `db/dev` on a real SQL Server 2022 and
is reproducible:

```
build/migrate.sh                       # db/01–14
build/migrate.sh dev/01_mock_sources.sql
build/migrate.sh dev/02_demo_content.sql
```

Pool: 398 people in the organisations `maseera.hrbp` is granted, out of a roster of 624.

---

## 1. Each candidate code is read against its own rule and its own source

This is the single most important correctness rule in the product, and it is the one an
implementation gets wrong most naturally — by resolving the equivalents and then applying
the *main* event's rule to all of them.

The naive column is "does a `Completed` record exist for exactly this item code". The
engine column is what `sel.usp_Framework_Attainment` returns.

| Event | Item code | Level | Must | Naive | Engine | Why they differ |
|---|---|---|---:|---:|---:|---|
| `EV-SAFE-FND` | `CRS-SAFE-01` | 1 | yes | 317 | **317** | agree |
| `EV-LEAD-TEAM` | `CRS-LEAD-01` | 1 | | 217 | **217** | agree |
| `EV-ASM-COG` | `ASM-COG-01` | 1 | | 153 | **153** | agree |
| `EV-SAFE-ADV` | `CRS-SAFE-02` | 2 | | 184 | **184** | agree |
| `EV-ASM-360` | `ASM-360-02` | 2 | | 147 | **93** | the event's own rule asks for a score of 75 or better |
| `EV-ACT-MGR` | `MGR1` | 2 | | 0 | **178** | SUM mode: sixty days summed over `sel.EmployeeCoverage`, which is not an `EmployeeRecord` row at all |
| `EV-LEAD-LEAD` | `CRS-LEAD-02` | 3 | yes | 107 | **161** | `CRS-LEAD-02B` also counts, and is read with **its own** event, rule and source |
| `EV-ASM-LEAD` | `ASM-LEAD-01` | 3 | | 145 | **145** | agree |
| `EV-ACT-DIR` | `DIR1` | 3 | | 0 | **98** | SUM mode, ninety days, and only rows whose `CoverageType` is `ACTING` |
| `EV-CAPITAL` | `CRS-CAP-02` | 4 | | 138 | **138** | agree |

Three of the differences are the whole design working:

- **`EV-ASM-360`: 147 → 93.** 147 people have a completed `ASM-360-02`. Only 93 of them
  scored 75 or better, and the event carries a condition set saying so. An engine that
  applied only the kind's default would over-count by 54 people, every one of whom would
  be told they were further along than they are.

- **`EV-LEAD-LEAD`: 107 → 161.** 107 people hold `CRS-LEAD-02`; 81 hold the older
  `CRS-LEAD-02B`; 161 hold one or the other. The engine reached the extra 54 by resolving
  the candidate codes and evaluating **each against its own event** — `CRS-LEAD-02B` has
  its own row in `sel.DevEvent`, its own kind and its own source. The drilldown names the
  code that did it:

  > `E10600` · Met via `CRS-LEAD-02B`

  An engine that resolved the equivalents but applied the main event's rule would get the
  same number here by luck, because both are plain course completions. It would get
  `EV-ASM-360` wrong the moment somebody adds an equivalent assessment with a different
  pass mark — which is exactly the kind of change this product exists to absorb.

- **`EV-ACT-DIR` and `EV-ACT-MGR`: 0 → 98 and 0 → 178.** Neither item is in
  `sel.EmployeeRecord` at all: both are SUM-mode requirements read from
  `sel.EmployeeCoverage`, summing days to a floor. `EV-ACT-DIR` additionally filters to
  `CoverageType = 'ACTING'`, which is why it is lower than `EV-ACT-MGR` despite a similar
  population — a stricter rule, not a broken one.

**The regression this pins:** if a change makes `EV-ASM-360` read 147, the condition set
stopped being applied. If it makes `EV-LEAD-LEAD` read 107, equivalences stopped being
resolved. If it makes either read a number between, each candidate code stopped being read
against its own rule.

---

## 2. The reason is never optional

Every requirement comes back with a sentence, met or not. `EngineTests` asserts this over
every requirement of a real person, and the profile screen prints it beside every row.

A requirement met through an equivalent says which code did it. A requirement met by a
measure says the number and the target: *"99 against 75"*. A requirement not met says what
was missing. A condition naming a field the source does not have fails **its own condition
only**, and says so — it does not fail the rule, and it does not silently pass.

---

## 3. The ladder and the summary cannot disagree

`sel.usp_Attainment_PerPerson` returns the requirements, the percentage and the ladder from
one evaluation. Every rung reports the same `AttainmentPct` the summary reports, because
there is one computation and three presentations of it. `EngineTests` asserts the equality
rung by rung.

A **must** not met sets `IsHeld` to false on every rung whatever the percentage says, and
the state word is the disqualification message from `cfg.Message`, not a number.

---

## 4. Where the pool actually falls

`sel.usp_Readiness_Spread` counts each person at the **highest** level they clear, so the
columns are a partition and not five overlapping counts.

| Level | Asks for | Clear the cut | At this level |
|---|---:|---:|---:|
| R1 · Ready now | 90% | 0 | 0 |
| R2 · Ready in 1–2 years | 75% | 4 | 4 |
| R3 · Ready in 3–5 years | 60% | 27 | 23 |
| R4 · Longer term | 40% | 84 | 57 |

Of the 398 in the pool: **314 hold no level yet**, and **267 are disqualified** by an
outstanding must requirement. Median attainment is 35%.

`ClearCut` counts everybody at or over the threshold; `AtThisLevel` counts only those for
whom this is the highest they reach. 84 clear 40% but 27 of those also clear 60%, so 57 sit
at R4. The two columns exist because the two questions get asked in different meetings.

---

## 5. Sampling says that it sampled

Above `ATTAINMENT_SAMPLE_CAP` (600 by default) the design-time preview takes an evenly
spaced sample, scales the counts back to the pool, and returns a `SampleNote`:

> Estimated from a sample of 600 of 12,000.

At 398 people this fixture does not sample, and the figures above are counted over
everybody: `IsSampled = 0`, `SampleCount = PoolCount = 398`, `SampleNote` null.
`EngineTests` asserts both halves — that a sampled summary carries a note and a smaller
sample count, and that an unsampled one counted the whole pool.

An estimate that does not say it is an estimate is a lie with a decimal point.

---

## 6. The engine is set-based

One statement per candidate code answers the whole pool. The framework attainment over 398
people and 11 candidate codes returns in well under a second; a per-person loop would be
398 × 11 = 4,378 evaluations, and at 79,000 people it would be 240,000 of them.

`EngineTests.The_engine_answers_the_whole_pool_in_one_pass_not_one_person_at_a_time` is a
smoke alarm rather than a benchmark: it fails long before a per-person loop would finish,
and it catches the shape going wrong rather than the timing wobbling.

---

## 7. The snapshot is written at open and never recomputed

`sel.CycleCandidate` is filled by `sel.usp_Cycle_Open` and by nothing else. Reading a
stage, drawing a funnel or running a report does not re-resolve the pool.

This is what makes a cycle auditable: somebody who left the company in March is still in
the January pool with the decision that was taken about them, and somebody who joined in
March is not retroactively in it. `EngineTests` asserts that reading a stage leaves the
candidate count unchanged.

`sel.CycleCandidateTrace` records why each person was in it — 1,194 traced criteria for
this fixture's 398 people — so the answer survives the criteria being edited afterwards.

---

## How to re-establish parity when the prototype turns up

1. Load the prototype's own fixture data into DB02 through `db/dev`-style scripts, or point
   `sel.TableMapping` at the prototype's tables.
2. Run `sel.usp_Framework_Attainment` for the same cycle and framework.
3. Compare `MetCount` per item code against the prototype's own figure.
4. Where they differ, run `sel.usp_Item_MetDetail` for that item and read the `Why` and
   `ViaCode` on the rows the two disagree about. The engine states its reasoning per
   person, which is what makes a disagreement diagnosable rather than merely visible.

Record the result here, replacing this section.
