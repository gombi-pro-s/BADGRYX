# ADR 0019: Load/performance testing — real Postgres query plans, real concurrent HTTP, no fabricated numbers

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had flagged load/performance testing as not started.
This sandbox has no live Supabase project, and (confirmed directly per ADR
0018) no `supabase` CLI and no reachable Docker daemon — there is no way to
run a full "real users hitting the real deployed stack" load test here.
That rules out faking a number ("handles 500 req/s") that nothing in this
environment actually measured. What's genuinely available:

1. A real local Postgres, with every migration and RLS policy applied —
   the same engine `scripts/run-sql-tests.sh` already uses for correctness.
   Nothing stops it from being seeded to a realistic volume and having its
   actual query plans inspected.
2. A real, running production build of the Next.js app (`next start`),
   for the handful of pages that don't need a live Supabase project to
   render (`/`, `/login`, `/signup` — none of them query the database).

## Decision

Two scripts, each honest about what it can and can't prove:

### `scripts/perf-test-sql.sh` + `scripts/perf/fixtures-and-queries.sql`

Rebuilds a throwaway local Postgres DB (via the existing
`scripts/local-test-db.sh`), seeds synthetic-but-constraint-valid volume —
300 users, dense `user_skill_states` coverage, `skill_evidence` and `scans`
rows deliberately skewed so one user ("perfuser1") has a much larger
personal history (300 evidence rows, 800 scans) than the rest — then runs
`EXPLAIN (ANALYZE, BUFFERS)` on this app's actual hot, user-scoped queries
(the dashboard's four queries, the skills matrix's three queries, the
scanner's list query), executed as that user through the same
`test_act_as()` role-switch the correctness SQL tests use, so RLS is
genuinely evaluated in the plan, not bypassed.

**What it gates on**: not absolute milliseconds. This sandbox's hardware is
shared and its performance characteristics aren't representative of any
real deployment target, so a hard millisecond budget would fail for
reasons unrelated to an actual regression. It gates on something
hardware-independent and structurally real instead: none of the three
queries against a table this test deliberately grew large
(`skill_evidence`, `user_skill_states`, `scans`) may fall back to a
sequential scan. If a future migration drops or narrows one of those
tables' indexes, this fails with a concrete, reproducible reason. Timings
are still printed for a human to eyeball trends across runs.

### `scripts/perf-test-http.mjs`

Hand-rolled (no new dependency — Node's built-in `fetch` and
`child_process`, matching this project's existing Turnstile hand-rolled
fetch/crypto approach) concurrent load generator. Starts a real `next
start` production server, fires concurrent requests at `/`, `/login`,
`/signup` for a configurable duration, and reports request count,
failures, throughput, and p50/p95/p99 latency per route.

**What it gates on**: zero request failures (5xx or a network-level
error) under concurrent load — a correctness signal ("did the server
survive"), not a speed claim. Latency numbers are printed, not gated, for
the same hardware-variance reason as the SQL script.

While verifying this script, found and fixed a real bug in it: the first
version spawned the server via `npx next start` and cleaned up with a
plain `server.kill()`. That reliably killed `npx` itself but not the
actual `next-server` process — `npx` forked it as a child rather than
exec-replacing itself with it, so killing only npx's pid orphaned the real
server (reparented to pid 1), which then sat there holding the port
indefinitely. Confirmed directly: a run left a `next-server` process alive
for 9+ minutes after the script had already printed its results and
exited. Fixed by spawning the local `next` binary directly (no `npx`
wrapper) in its own process group (`detached: true`) and killing the whole
group by its negative pid, with a `SIGTERM`-then-`SIGKILL` grace period
and a synchronous `process.on("exit", ...)` safety net for any path that
skips the graceful teardown. Re-verified: a subsequent run left no process
listening on the port afterward.

## Why

Both scripts measure something real in this environment rather than
padding the checklist with an invented number. Structural assertions (no
seq scan; no request failures) instead of hardware-dependent absolute
thresholds keep the tests meaningful and non-flaky across very different
machines — a contributor's laptop, this sandbox, and CI will all report
different latencies but should all agree on whether an index got dropped
or the server fell over under load.

## Consequences

- Neither script is wired into CI. An HTTP load test on a shared,
  variable-performance CI runner produces noisy numbers nobody can act on,
  and the SQL script's fixture generation (hundreds of thousands of rows)
  adds real minutes to every CI run for a signal that doesn't change
  between commits unless an index actually changes. Both are meant to be
  run manually — locally, or in a dedicated benchmarking environment
  before a real release — documented in `RELEASE_CHECKLIST.md` and this
  ADR rather than silently absent from `.github/workflows/ci.yml`.
- Real results from a run in this sandbox (hardware-dependent, not a
  universal guarantee, but proof the scripts work and a baseline to watch
  for regressions against):
  - SQL: all 8 queries executed in under 2ms each; zero sequential scans
    on `skill_evidence`, `user_skill_states`, or `scans` despite one user
    having 300/800 rows respectively amid a table shared with 299 other
    users.
  - HTTP: 3675 requests across `/`, `/login`, `/signup` combined (20
    concurrent workers, 15s), 0 failures. Per-route: `/` p50=104ms/
    p95=142ms/p99=214ms; `/login` p50=91ms/p95=183ms/p99=290ms; `/signup`
    p50=31ms/p95=103ms/p99=204ms — see `RELEASE_CHECKLIST.md` for the
    same figures in context. (These are from the run after the process-
    cleanup fix below; an earlier run reported 3638/0 failures with
    similar latencies, confirming the fix changed nothing about the
    measurement itself, only the teardown.)
- This does not exercise any authenticated, database-backed route (every
  such route needs a live Supabase project to render at all — the same
  limitation every other phase in this session has hit). A real
  production load test against `/dashboard`, `/skills`, `/labs/[labId]`'s
  terminal, etc. still needs a provisioned Supabase project and a real
  deployment target (`MANUAL_SETUP.md` §2, §5).
