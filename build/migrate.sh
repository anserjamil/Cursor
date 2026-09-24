#!/usr/bin/env bash
# Copy db/ into the SQL Server container and run a migration script with SQLCMD mode on.
# Usage: build/migrate.sh [script]     (default: 00_run_all.sql)
set -euo pipefail
SCRIPT="${1:-00_run_all.sql}"
docker exec maseera-sql rm -rf /db 2>/dev/null || true
docker cp /home/user/Cursor/db/. maseera-sql:/db >/dev/null
exec docker exec -w /db maseera-sql /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "${MSSQL_SA_PASSWORD:-Maseera!Dev2026}" -C -d DB02 -b -I -i "$SCRIPT"
