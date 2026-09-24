# Running Maseera

## Setting up a local database

There is a script for this, because the steps below are the same every time and getting
one of them slightly wrong produces an error a long way from its cause.

```powershell
.\build\setup-local.ps1 -WithDemoData
```

```bash
build/setup-local.sh --with-demo
```

It finds a SQL Server you can already reach — trying the local default instance, then
`.\SQLEXPRESS`, then LocalDB — creates DB02, runs the whole migration, and with
`-WithDemoData` loads the development fixture so there is something to look at. Running it
twice is the normal case: the migration is idempotent and an existing DB02 is migrated over
rather than replaced. `-Recreate` drops it first, and asks before it does.

Neither script needs Docker. Both refuse to do anything if `sqlcmd` is missing and say how
to get it.

### If you have no SQL Server yet

Any of these is enough, and none of them is Docker:

| | |
|---|---|
| **Developer Edition** | Free, full featured, closest to production. [Download](https://www.microsoft.com/sql-server/sql-server-downloads) |
| **Express** | Free, smaller, plenty for this. `winget install Microsoft.SQLServer.2022.Express` |
| **LocalDB** | The lightest: no service, starts on demand. Comes with the Visual Studio "Data storage and processing" workload, or the Express installer's LocalDB option. |

On Linux, SQL Server installs natively from Microsoft's apt or yum repositories. On macOS
it does not exist natively at all — there, it is Docker, a Linux VM, or a server elsewhere
on the network, and `build/setup-local.sh` with `MASEERA_SERVER` set will reach the last
of those.

### A password is never put on a command line

Both scripts prompt for a SQL login's password and pass it through `SQLCMDPASSWORD`, which
`sqlcmd` reads itself. A password given as `-P` is visible to every other process on the
machine for as long as the command runs; an environment variable set for one process and
its children is not. The scripts clear it again when they finish.

Windows authentication needs none of this, and is the default.

---

## The database

There is **one** database and its name is **DB02**. The application never builds a
connection string in code, never logs one, and never opens a second. Nothing reads,
references or migrates anything from DB01.

### Migrating

Migrations are run by a separate SQLCMD step, **never by the application at startup**. An
application that migrates its own schema needs rights it should not have for the other
twenty-three hours of the day.

```
sqlcmd -S <server> -d DB02 -E -b -I -i db\00_run_all.sql
```

- `-b` so a failure stops the run with a non-zero exit code.
- `-I` for SQLCMD mode, which `:r` needs.
- `-E` for Windows authentication, or `-U`/`-P` where that is how the server is reached.

`00_run_all.sql` runs `01`–`14` in order and then prints a receipt: every configuration and
reference table with its row count, and every business table with whether it holds data. It
`RAISERROR`s if a configuration or reference table came out empty, because a silently empty
`cfg.Message` is a screen full of blank sentences.

The scripts are **idempotent**. Every object is `CREATE OR ALTER`, every seed is a `MERGE`,
and running `00_run_all.sql` twice on the same database is the normal case — that is how an
upgrade is applied.

### Rights the application needs

The application pool runs as a domain account that holds:

- `EXECUTE` on the `cfg`, `sel`, `sec` and `audit` schemas, and
- `SELECT` on the roster and evidence tables in `dbo`.

**Not `db_owner`.** Not `db_datawriter` either: every write goes through a procedure, so
the account has no need to write a table directly and should not be able to.

```sql
CREATE USER [DOMAIN\svc_maseera] FOR LOGIN [DOMAIN\svc_maseera];
GRANT EXECUTE ON SCHEMA::cfg   TO [DOMAIN\svc_maseera];
GRANT EXECUTE ON SCHEMA::sel   TO [DOMAIN\svc_maseera];
GRANT EXECUTE ON SCHEMA::sec   TO [DOMAIN\svc_maseera];
GRANT EXECUTE ON SCHEMA::audit TO [DOMAIN\svc_maseera];
GRANT SELECT  ON SCHEMA::dbo   TO [DOMAIN\svc_maseera];
```

The migration step runs as somebody else — a deployment account with the rights to create
objects — and that account is not the one the application uses.

### The connection string

Supplied by the customer, and kept as supplied except for the database name and an
application name:

```
Data Source=.;Initial Catalog=DB02;Integrated Security=True;Persist Security Info=False;
Pooling=True;MultipleActiveResultSets=False;Connect Timeout=30;Encrypt=False;
TrustServerCertificate=True;Packet Size=4096;Command Timeout=0;Application Name=Maseera
```

Three parts of it are load-bearing:

- **`Pooling=True`** in `appsettings.json`. The customer's string had pooling off, which is
  right on a developer's machine and wrong anywhere with real traffic: without a pool,
  every request pays a full connection handshake. `appsettings.Development.json` keeps it
  off, deliberately, so a developer restarting the application repeatedly gets connections
  closed rather than held.
- **`Command Timeout=0`** means no timeout at the connection level. The application sets a
  per-command timeout from `Maseera:CommandTimeoutSeconds` (120 by default) instead, so a
  runaway preview cannot hold a request open forever.
- **`MultipleActiveResultSets=False`** means one open reader at a time. Every multi-set
  read consumes its grid completely before the next call.

`Encrypt=False` and `TrustServerCertificate=True` are the customer's choices, not
recommendations. On a network where the database is not on the same machine, they are worth
revisiting with whoever owns that network.

---

## The application

### Configuration

| Key | What it does |
|---|---|
| `ConnectionStrings:Db02` | The one connection string. The application throws loudly at startup if it is missing, rather than failing on the first screen that needs a row. |
| `Maseera:CommandTimeoutSeconds` | Per-command timeout, because the connection string sets none. |
| `Maseera:AsOfOverride` | Run the whole application as if it were this day. `cfg.Setting 'AS_OF_OVERRIDE'` does the same for the database, and the two are meant to agree. |
| `Maseera:RosterSchema` | The schema the customer's operational tables sit in. |
| `Maseera:AllowImpersonation` | The "Sign in as" switcher. See below. |
| `Maseera:DevelopmentLogin` | The login used when Windows authentication is not available. |

### Authentication

Windows authentication (Negotiate). In IIS, enable Windows authentication and disable
anonymous.

The **"Sign in as" switcher** is gated twice: on `IWebHostEnvironment.IsDevelopment()`
first, and on `Maseera:AllowImpersonation` second. Setting the flag true in production
changes nothing, because the first gate has already closed. That ordering is deliberate —
a configuration file is easier to get wrong than a build.

### Authorization

Access is decided by six rules applied in order, in `sec.fn_ScreenAccessAsOf`:

1. **Bootstrap** — the seeded administrator, so a fresh database is always reachable.
2. **Not registered** — no user record, denied before anything else is considered.
3. **Expired** — authorization ended before the as-of date, denied.
4. **User override** — a grant against this person replaces the role rule outright.
5. **Role policy** — the grant their role carries for this screen.
6. **No rule** — nothing grants it, denied.

`sec.fn_ScreenAccessRule` returns which rule decided, and the Access screen renders it, so
a denial is explainable rather than mysterious.

`AUDITOR` carries `IsReadOnly`. **No grant can give it write** — not a role grant, not a
user override. `SecurityTests` sets the most permissive override there is against the
auditor and asserts the answer is still read.

### Row-level security

Every read joins the row's `OrgCode` to `sec.fn_UserOrgScope(@LoginName)` — **including the
drilldown behind every count**. A grant on a node grants everything beneath it, through
`sel.OrgAncestor`.

Two people looking at the same cycle will not see the same numbers. That is the scope
working. The **Row-level security** screen compares two viewers' scopes side by side so
that stops being surprising, and the Cycles screen says so in its hero band.

`sec.RlsBypass` is the explicit, audited exception. The administrator is in it.

### Test mode

Administrator-only, and every decision taken in it is stamped `TEST` in
`sel.CandidateDecision`. The stamp is written when the decision is taken and is never
removed: the Decision log, the profile and every report show it.

---

## Deploying

1. Migrate: `sqlcmd ... -i db\00_run_all.sql`, as the deployment account. Check the
   receipt.
2. Publish: `dotnet publish src/Maseera.Web -c Release`.
3. Point the site at the publish output. The app pool identity is the service account
   above.
4. Open `/Admin/Health`. Everything green means the database is reachable, every
   configuration table has rows, every registered screen resolves to a real controller
   action, and every requirement kind has a table mapped.

The same self-check runs at startup. Outside Development it **throws** on a fatal finding
rather than starting: fail loudly here rather than quietly on the screen that needed the
row.

`/Admin/Health/Live` is the terse endpoint for a load balancer — a status code and a word,
with nothing about the database's shape in it.

### There is no build step for the front end

Bootstrap 5.3 is vendored as compiled CSS and its custom properties are overridden from
`:root`. The Sass layer compiles during `dotnet build`. The JavaScript is four ES2022
modules served as they are. IBM Plex is self-hosted in `wwwroot/fonts`.

The tool runs on a restricted network: **no CDN, ever** — not for the stylesheet, not for
the script, not for the fonts. `ViewDisciplineTests` scans every view for an absolute
`src` or `href` and fails on one.

---

## Loading data

Both loads are re-runnable and neither is destructive:

- **Load the roster** (`sel.usp_Roster_Load`) reads the mapped roster table into
  `sel.Employee` and rebuilds the organisation closure.
- **Sync the evidence** (`sel.usp_Evidence_SyncAll`) reads every mapped source into
  `sel.EmployeeRecord`, `sel.EmployeeCoverage` and `sel.EmployeePmp`, and rebuilds the
  metrics.

Both are on the **Load exceptions** screen, which is also where anything that could not be
placed ends up.

`sel.OrgNode` is learned from the roster and from nothing else, so a unit nobody is in is a
unit the tree never hears about — and a grant on it would then match nothing. If the tree
looks short, check that the roster carries a row for every level, not only the leaves.

---

## Tests

```
dotnet test                                  # the unit tests
MASEERA_TEST_DB02="..." dotnet test          # and the database tests as well
```

`tests/Maseera.Tests.Unit` needs nothing: it covers the share formatter, the as-of
comparisons, the access precedence and the four states of a grant, and it scans the views
for a stray percentage, a CDN link, a colour written into markup or SQL text.

`tests/Maseera.Tests.Sql` needs a DB02 to read and **skips with a sentence** when
`MASEERA_TEST_DB02` is not set, because "no database here" is a different finding from "the
engine is wrong". It covers the procedure contract — generated by scanning the repositories
rather than listed by hand — the six access rules, the two-viewer scope comparison, the
read-only auditor, the engine's equivalence handling, sampling, the snapshot, and the
idempotency of the seeds.

`docs/parity.md` records what the engine currently answers, and why those numbers are the
right ones.

---

## Things that will bite

**A new roster column needs no migration.** Press *Re-read the columns* on the Roster
fields screen. It arrives switched off.

**Marking a field sensitive switches it off as a criterion** in the same statement. The two
cannot disagree, so do not expect to have both.

**A closed cycle is never changed, only copied.** Every save refuses on one, with that
sentence.

**A decision is never overwritten.** Clearing one writes a row too. The Decision log is the
history, not the current state.

**The pool is a snapshot.** Editing the criteria of an open cycle changes what a *new*
cycle would resolve to and changes nothing about this one. That is the point.

**An unmapped source is not a zero.** Every screen that would have counted it says so
instead.
