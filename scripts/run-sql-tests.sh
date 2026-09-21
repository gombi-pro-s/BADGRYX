#!/usr/bin/env bash
# ============================================================================
# Rebuilds the local test database from every migration, then runs every
# supabase/tests/*.sql regression file against it in order. Used locally and
# by CI (.github/workflows/ci.yml).
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="${1:-icorepen_test}"

bash "${ROOT_DIR}/scripts/local-test-db.sh" "${DB_NAME}"

echo ""
echo "==> Running SQL regression tests"
for f in "${ROOT_DIR}"/supabase/tests/[0-9]*.sql; do
  echo ""
  echo "---- $(basename "$f") ----"
  if [ -n "${CI:-}" ]; then
    PGPASSWORD="${PGPASSWORD:-postgres}" psql -v ON_ERROR_STOP=1 \
      -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
      -d "${DB_NAME}" -f "$f"
  else
    su postgres -c "psql -v ON_ERROR_STOP=1 -d ${DB_NAME} -f $f"
  fi
done

echo ""
echo "==> All SQL regression tests passed."
