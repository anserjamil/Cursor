#!/usr/bin/env bash
# Run sqlcmd against the local development SQL Server container.
# Usage: build/sql.sh -Q "SELECT 1"      |  build/sql.sh -i db/00_run_all.sql
set -euo pipefail
exec docker exec -i maseera-sql /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "${MSSQL_SA_PASSWORD:-Maseera!Dev2026}" -C -b "$@"
