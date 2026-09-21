#!/usr/bin/env bash
# ============================================================================
# Rebuilds a local Postgres database that stands in for a Supabase project's
# database (auth schema stub + anon/authenticated/service_role roles), then
# applies every migration under supabase/migrations/ in order.
#
# This lets migrations and RLS policies be verified against a real Postgres
# engine in CI and in local development, without requiring Docker (used by
# `supabase start`) or a live Supabase project.
#
# Usage: scripts/local-test-db.sh [database-name]
# Requires: a running Postgres server reachable as the `postgres` superuser
#           (locally via `sudo -u postgres` / `su postgres`, in CI via
#           PGHOST/PGPORT/PGUSER/PGPASSWORD env vars for the postgres role).
# ============================================================================
set -euo pipefail

DB_NAME="${1:-icorepen_test}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Runs a SQL string as the postgres superuser, optionally against a specific
# database (second arg). Avoids word-splitting issues by writing the SQL to
# a temp file and using -f, instead of passing it through -c across an `su`
# boundary.
sql_exec() {
  local sql="$1"
  local db="${2:-postgres}"
  local tmp
  tmp="$(mktemp)"
  printf '%s\n' "$sql" > "$tmp"
  chmod 644 "$tmp"
  if [ -n "${CI:-}" ]; then
    PGPASSWORD="${PGPASSWORD:-postgres}" psql -v ON_ERROR_STOP=1 \
      -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
      -d "$db" -f "$tmp"
  else
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $db -f $tmp"
  fi
  rm -f "$tmp"
}

sql_file() {
  local file="$1"
  local db="$2"
  if [ -n "${CI:-}" ]; then
    PGPASSWORD="${PGPASSWORD:-postgres}" psql -v ON_ERROR_STOP=1 \
      -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
      -d "$db" -f "$file"
  else
    su postgres -c "psql -v ON_ERROR_STOP=1 -d $db -f $file"
  fi
}

echo "==> Dropping and recreating database: ${DB_NAME}"
sql_exec "DROP DATABASE IF EXISTS ${DB_NAME};"
sql_exec "CREATE DATABASE ${DB_NAME};"

echo "==> Creating Supabase-equivalent roles"
sql_exec "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'postgres';
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
  END IF;
END
\$\$;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
" "${DB_NAME}"

echo "==> Applying auth stub bootstrap"
sql_file "${ROOT_DIR}/supabase/tests/bootstrap/0000_auth_stub.sql" "${DB_NAME}"

echo "==> Applying migrations"
for f in "${ROOT_DIR}"/supabase/migrations/*.sql; do
  echo "   -- $(basename "$f")"
  sql_file "$f" "${DB_NAME}"
done

echo "==> Done. Database '${DB_NAME}' is ready."
