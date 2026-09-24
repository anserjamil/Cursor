# Maseera

An internal succession, talent and development management application.

Three kinds of cycle over one design model — **talent review**, **succession** and
**development** — plus three configuration areas: cycle design, the development framework,
and reference and mapping data.

It is a serious administrative tool used daily by a small number of trained people.
Density, legibility and explaining decisions matter far more than delight.

## The two rules everything else follows from

**1. Nothing is hardcoded.** There is no literal list, status, operator, level, label,
threshold, menu caption or colour in C#, Razor or JavaScript. Statuses are
`cfg.DomainValue`. Operators are `cfg.Operator`, with their SQL shape and arity. Caps and
page sizes are `cfg.Setting`. The navigation is `cfg.MenuGroup` and `cfg.Screen`. Wizard
steps are `sel.WizardStep`, recipes `sel.CycleRecipe`, validations `sel.ValidationRule`.
Sentences are `cfg.Message`. A state's colour is a `SemanticRole` that becomes a class.

A C# enum mirroring a domain is the failure mode this exists to avoid.

**2. All business logic lives in SQL Server.** Controllers call procedures and pass the
results to views. C# does not evaluate a rule, resolve a pool, decide what "completed"
means, compute a percentage, compose a `WHERE`, or choose which stage is open. There is no
SQL text in C# at all — not even a `SELECT 1`; the health check calls a procedure too.

Three presentation calculations are allowed in C#, and only three: turning a count and a
total into words, formatting a date against the as-of date, and building a CSS class name
from a semantic role.

## The stack

| | |
|---|---|
| Runtime | .NET 9, ASP.NET Core MVC 9 — controllers, Razor views, areas |
| Data | Dapper over `Microsoft.Data.SqlClient`, calling stored procedures |
| ORM | none. EF Core may not express a rule, a pool, a percentage or a predicate |
| CSS | Bootstrap 5.3 plus a Sass token layer |
| JS | four plain ES2022 modules. No framework, no bundler |
| Fonts | IBM Plex, self-hosted. The tool runs on a restricted network: no CDN, ever |
| Auth | Windows authentication, with a development-only impersonation switcher |
| Export | CSV and XLSX. No PDF |
| Viewport | desktop first, 1440×900 and 1280×800; must not break below 992px |

## Laid out

```
db/           01–14, applied by SQLCMD. Never by the application.
  dev/        a development-only fixture: mock source tables and demo content
src/
  Maseera.Core   records, and the three presentation helpers
  Maseera.Data   the connection factory, the procedure runner, the repositories
  Maseera.Sql    a home for database assets
  Maseera.Web    controllers, views, view components, tag helpers, Sass, JS, fonts
tests/
  Maseera.Tests.Unit  needs nothing
  Maseera.Tests.Sql   needs a DB02 to read; skips with a sentence without one
docs/
  screens.md    every screen, what it is for, and how it is registered
  mapping.md    every table read, and what breaks when it is not mapped
  parity.md     what the engine answers today, and why those are the right numbers
  runbook.md    migrating, deploying, rights, loads, and what will bite
```

## Getting it running

See [`docs/runbook.md`](docs/runbook.md). In short:

```
sqlcmd -S <server> -d DB02 -E -b -I -i db/00_run_all.sql
dotnet run --project src/Maseera.Web
```

Then open `/Admin/Health` and check that everything is green.

## Scale it is built for

~79,000 employees across ~2,942 organisation units eight levels deep, a ~200-column
employee record, two or three live cycles, pools from hundreds to tens of thousands, and
tens of concurrent users.

Every list survives 12,000 rows because every list is paged on the server. The evaluation
engine is set-based: one statement per candidate code answers the whole pool, rather than
one evaluation per person.

## A note on provenance

The foundation documents the build prompt treats as given — the prototype
`Maseera.dc.html`, the `db02/00`–`09` documents and the handoff notes — are **not present
in this repository**. The schema, reference data and engine were reconstructed from the
object inventory in Part 3.2 and the behavioural descriptions in Parts 8 and 9.

Engine parity against the prototype therefore has not been established.
[`docs/parity.md`](docs/parity.md) records what the engine answers today and how to
re-establish parity when those documents turn up.
