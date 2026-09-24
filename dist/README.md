# Ready-made database

Three ways to get DB02 onto a SQL Server you already have. Pick one.

Everything here is **generated** — `build/flatten.sh` builds the `.sql` files from `db/`.
Do not edit them: edit the source and run the generator again. A copy that has drifted
from its source is worse than no copy.

---

## 1 · The scripts (works on any SQL Server version)

```sql
CREATE DATABASE DB02;
```

Then, in SSMS: open the file, **pick DB02 in the database dropdown**, press **F5**.

| File | What it does |
|---|---|
| `maseera-schema.sql` | The whole thing: 5 schemas, ~60 tables, 164 stored procedures, and all the reference data — statuses, operators, screens, messages, validation rules, roles, grants. |
| `maseera-demo-data.sql` | Optional. 624 invented people, a development framework, and an open cycle with 398 in the pool. |

Or from a command line:

```
sqlcmd -S <server> -d DB02 -E -b -i maseera-schema.sql
sqlcmd -S <server> -d DB02 -E -b -i maseera-demo-data.sql
```

No SQLCMD mode needed, no `-I` flag needed. Both files set `QUOTED_IDENTIFIER` themselves,
because SSMS connects with it on and `sqlcmd` connects with it off — and a filtered index
cannot be created without it. Leaving that to the client is how the same file works in one
and fails halfway through in the other.

**They are idempotent.** Running `maseera-schema.sql` again over a populated database is
the normal case — that is how an upgrade is applied, and it leaves the data alone.

**They refuse to run against anything but DB02.** If the wrong database is selected, the
script says so and stops rather than scattering 164 procedures into `master`.

### About `maseera-demo-data.sql`

It **creates and fills the `dbo.*` tables the application reads** — the roster, course
completions, assessments, coverage, performance. If a real server already holds data in
tables by those names, this replaces it.

Only run it on a scratch database.

---

## 2 · The backup (SQL Server 2022 or later only)

`DB02.bak` — 3.3 MB, compressed, with the schema, the reference data **and** the demo data
already in it.

```sql
RESTORE DATABASE DB02
FROM DISK = N'C:\path\to\DB02.bak'
WITH MOVE N'DB02'     TO N'C:\path\to\DB02.mdf',
     MOVE N'DB02_log' TO N'C:\path\to\DB02_log.ldf',
     RECOVERY;
```

In SSMS: right-click **Databases** → **Restore Database** → **Device** → pick the file.

> **It was taken on SQL Server 2022 (16.0), so it will only restore to 2022 or later.**
> A backup can never be restored to an older version than it was taken on. On 2019, 2017 or
> 2016, use the scripts above — they work on any version.
>
> Check yours with `SELECT @@VERSION`.

---

## 3 · The setup script (does all of the above for you)

```powershell
..\build\setup-local.ps1 -WithDemoData
```

Finds a SQL Server you can reach, creates DB02, migrates it, loads the demo data.

---

## Then

```
dotnet run --project src\Maseera.Web
```

`appsettings.Development.json` already points at the local default instance. For anything
else, set it in the same terminal rather than editing a file that is in git:

```powershell
$env:ConnectionStrings__Db02 = "Data Source=.\SQLEXPRESS;Initial Catalog=DB02;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;Application Name=Maseera"
```

Open **http://localhost:5180** and check `/Admin/Health` is green.

---

## The application does not create these tables itself

That is deliberate, and it is worth knowing before you go looking for the setting that
turns it on.

The account the application runs as holds `EXECUTE` on four schemas and `SELECT` on `dbo`
— nothing more. It cannot create a table, alter one, or drop one. Migrations are a separate
step, run by a separate account with the rights to do it.

An application that can rewrite its own schema has those rights for the other twenty-three
hours of the day as well.
