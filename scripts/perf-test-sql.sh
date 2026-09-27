#!/usr/bin/env bash
# ============================================================================
# Load/performance test for this app's actual hot, user-scoped queries
# (dashboard, skills matrix, scanner list) against a real local Postgres
# with every migration and RLS policy applied -- the same harness
# run-sql-tests.sh uses, just with a throwaway DB seeded to a realistic
# volume instead of a handful of correctness fixtures.
#
# What this gates on: NOT absolute millisecond thresholds -- this sandbox's
# hardware is shared/variable, so a hard-coded ms budget would fail for
# reasons that have nothing to do with a real regression. What it DOES gate
# on is structural: none of the three queries this app actually issues per
# request against a table this test deliberately grows large (skill_evidence,
# user_skill_states, scans) may fall back to a sequential scan on that
# table. If someone drops or breaks one of those tables' indexes, this
# fails with a real, reproducible reason -- not "it was slow this time."
# Timings are still printed, for a human to eyeball trends across runs.
#
# Usage: scripts/perf-test-sql.sh [database-name]
# Requires the same Postgres access as scripts/run-sql-tests.sh.
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="${1:-icorepen_perf}"
LOG_FILE="$(mktemp)"
trap 'rm -f "${LOG_FILE}"' EXIT

bash "${ROOT_DIR}/scripts/local-test-db.sh" "${DB_NAME}"

echo ""
echo "==> Seeding realistic volume and running EXPLAIN ANALYZE on hot queries"
if [ -n "${CI:-}" ]; then
  PGPASSWORD="${PGPASSWORD:-postgres}" psql -v ON_ERROR_STOP=1 \
    -h "${PGHOST:-127.0.0.1}" -p "${PGPORT:-5432}" -U "${PGUSER:-postgres}" \
    -d "${DB_NAME}" -f "${ROOT_DIR}/scripts/perf/fixtures-and-queries.sql" | tee "${LOG_FILE}"
else
  su postgres -c "psql -v ON_ERROR_STOP=1 -d ${DB_NAME} -f ${ROOT_DIR}/scripts/perf/fixtures-and-queries.sql" | tee "${LOG_FILE}"
fi

echo ""
echo "==> Query timings"
awk '
  /^=== QUERY / { name = $3; next }
  /Execution Time:/ { print name ": " $0; name = "" }
' "${LOG_FILE}"

echo ""
echo "==> Checking for sequential scans on the tables this test deliberately grew large"
FAIL=0
for TABLE in skill_evidence user_skill_states scans; do
  if grep -q "Seq Scan on ${TABLE}" "${LOG_FILE}"; then
    echo "FAIL: query plan used a sequential scan on '${TABLE}' -- its index isn't being used (dropped? RLS policy shape changed? query no longer matches the index?)."
    FAIL=1
  else
    echo "PASS: no sequential scan on '${TABLE}'."
  fi
done

if [ "${FAIL}" -ne 0 ]; then
  echo ""
  echo "==> Load/performance test FAILED. Full EXPLAIN output is above."
  exit 1
fi

echo ""
echo "==> Load/performance test passed."
