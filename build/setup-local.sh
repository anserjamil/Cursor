#!/usr/bin/env bash
#
# Creates DB02 on a SQL Server you already have, and runs the whole migration. No Docker.
#
# The same thing build/setup-local.ps1 does, for a shell. Use it on Linux, where SQL
# Server installs natively, or against a server somewhere else on the network.
#
#   MASEERA_SERVER   the instance to use              (default: localhost)
#   MASEERA_USER     a SQL login                      (default: Windows/integrated)
#   SQLCMDPASSWORD   its password, read by sqlcmd itself so it never reaches a command
#                    line, where every other process on the machine could read it
#
# Usage:
#   build/setup-local.sh                # schema only
#   build/setup-local.sh --with-demo    # and the development fixture
#   build/setup-local.sh --recreate     # drop DB02 first; asks first
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_FOLDER="$REPO_ROOT/db"

SERVER="${MASEERA_SERVER:-localhost}"
WITH_DEMO=0
RECREATE=0

for arg in "$@"; do
    case "$arg" in
        --with-demo) WITH_DEMO=1 ;;
        --recreate)  RECREATE=1 ;;
        -h|--help)   sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# sqlcmd is not always on PATH; this is where the Linux packages put it.
SQLCMD="$(command -v sqlcmd || true)"
[ -z "$SQLCMD" ] && [ -x /opt/mssql-tools18/bin/sqlcmd ] && SQLCMD=/opt/mssql-tools18/bin/sqlcmd
[ -z "$SQLCMD" ] && [ -x /opt/mssql-tools/bin/sqlcmd ]   && SQLCMD=/opt/mssql-tools/bin/sqlcmd

if [ -z "$SQLCMD" ]; then
    cat >&2 <<'MSG'

sqlcmd was not found. On Ubuntu or Debian:

    curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
    sudo apt-get update && sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18
    export PATH="/opt/mssql-tools18/bin:$PATH"
MSG
    exit 1
fi

AUTH=()
if [ -n "${MASEERA_USER:-}" ]; then
    if [ -z "${SQLCMDPASSWORD:-}" ]; then
        read -r -s -p "Password for $MASEERA_USER: " SQLCMDPASSWORD
        echo
        export SQLCMDPASSWORD
    fi
    AUTH=(-U "$MASEERA_USER")
else
    AUTH=(-E)
fi

# sqlcmd 18 encrypts by default and a local instance usually has a self-signed
# certificate, so -C trusts it. Older builds do not know the flag.
TRUST=()
"$SQLCMD" -? 2>&1 | grep -qE '^\s*\[?-C\b' && TRUST=(-C)

say()  { printf '\n\033[36m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m%s\033[0m\n' "$1"; }
note() { printf '  \033[90m%s\033[0m\n' "$1"; }
bad()  { printf '\033[31m%s\033[0m\n' "$1" >&2; }

run_sql()    { "$SQLCMD" -S "$SERVER" "${AUTH[@]}" "${TRUST[@]}" -b "$@"; }
scalar()     { run_sql -h -1 -W -Q "SET NOCOUNT ON; $1" 2>/dev/null | head -1 | tr -d '[:space:]'; }
scalar_db()  { run_sql -d DB02 -h -1 -W -Q "SET NOCOUNT ON; $1" 2>/dev/null | head -1 | tr -d '[:space:]'; }

note "sqlcmd: $SQLCMD"

say "Looking for a SQL Server you can reach"
if ! run_sql -Q "SELECT 1" >/dev/null 2>&1; then
    bad ""
    bad "$SERVER did not answer."
    bad "Check the name, that the service is running, and that you can sign in."
    bad "Set MASEERA_SERVER to point somewhere else."
    exit 1
fi
ok "$SERVER answered"
note "$(scalar "SELECT CONVERT(nvarchar(200), SERVERPROPERTY('Edition'))")"

say "DB02"
EXISTS="$(scalar "SELECT COUNT(*) FROM sys.databases WHERE name = 'DB02'")"

if [ "$EXISTS" = "1" ] && [ "$RECREATE" = "1" ]; then
    printf '  \033[33mDrop DB02? Everything in it is lost. Type DB02 to confirm: \033[0m'
    read -r answer
    if [ "$answer" != "DB02" ]; then
        note "Left alone. Nothing was changed."
        exit 1
    fi
    run_sql -Q "ALTER DATABASE DB02 SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE DB02;" >/dev/null
    ok "dropped"
    EXISTS=0
fi

if [ "$EXISTS" = "1" ]; then
    ok "already there — the migration is idempotent, so it runs over it"
else
    run_sql -Q "CREATE DATABASE DB02" >/dev/null
    ok "created"
fi

say "Running db/00_run_all.sql"
note "The receipt at the end is the check: every configuration and reference"
note "count must be non-zero."
echo

# 00_run_all.sql pulls in 01-14 with :r, and those paths are relative to it.
cd "$DB_FOLDER"
run_sql -d DB02 -I -i 00_run_all.sql
cd - >/dev/null
ok "schema and reference data applied"

if [ "$WITH_DEMO" = "1" ]; then
    say "Loading the development fixture"
    note "This creates and fills the dbo.* tables the application reads. Do not do"
    note "this on a server holding real data in tables by those names."
    echo
    cd "$DB_FOLDER"
    for script in dev/01_mock_sources.sql dev/02_demo_content.sql; do
        note "running $script"
        run_sql -d DB02 -I -i "$script"
    done
    cd - >/dev/null
    ok "roster loaded, framework built, cycle opened"
fi

say "Done"
PEOPLE="$(scalar_db "SELECT COUNT(*) FROM sel.Employee")"

if [ -n "${MASEERA_USER:-}" ]; then
    AUTH_PART="User ID=$MASEERA_USER;Password=<yours>"
else
    AUTH_PART="Integrated Security=True"
fi

cat <<MSG

  Point the application at it:

    export ConnectionStrings__Db02="Data Source=$SERVER;Initial Catalog=DB02;$AUTH_PART;Encrypt=False;TrustServerCertificate=True;Application Name=Maseera"

  Run it:

    dotnet run --project src/Maseera.Web

  Then open http://localhost:5180 and check /Admin/Health is green.
MSG

if [ "${PEOPLE:-0}" = "0" ]; then
    echo
    note "There is nobody in the database yet. For something to look at:"
    note "    build/setup-local.sh --with-demo"
else
    echo
    note "$PEOPLE people on the roster."
fi
