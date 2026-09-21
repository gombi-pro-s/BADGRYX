# ADR 0003: Skill Graph state machine, computed only from server-verified evidence

## Status

Accepted.

## Context

The product's core differentiator (spec sections 4-5) is that "course
completion" must never equal "skill mastery." A naive implementation would
let a client set `user_skills.mastered = true` directly, which is exactly
the failure mode the product is designed to avoid.

## Decision

- `skill_evidence` is an append-only table. Every row records one graded
  interaction: `evidence_type` (`theory | quiz | guided_lab | unguided_lab |
  ctf | assessment | remediation | retest`) and `outcome`
  (`passed | failed | partial`).
- `user_skill_states` is a derived table, one row per (user, skill), never
  written directly. It is recomputed by `public.recompute_skill_state()`
  every time new evidence is recorded.
- Neither table has any INSERT/UPDATE/DELETE grant for `authenticated` or
  `anon`. The only writer is `public.record_skill_evidence()`, an internal
  `SECURITY DEFINER` function with no EXECUTE grant to `authenticated`
  either — it is only callable by other `SECURITY DEFINER` grading
  functions (`submit_quiz_attempt()`, `submit_lab_flag()`,
  `submit_ctf_flag()`) that have independently verified the outcome first
  (a hidden quiz answer key, a hashed lab/CTF flag compared server-side).
- The state machine rules (documented in full in
  `supabase/migrations/20260921000006_skill_graph.sql`) are:

  | Evidence present | State |
  |---|---|
  | none | `NOT_STARTED` |
  | passed `theory` | `LEARNING` |
  | passed `guided_lab` or `quiz` | `PRACTICING` |
  | passed `assessment` | `ASSESSED` |
  | passed `unguided_lab` or `ctf` | `DEMONSTRATED` |
  | passed `assessment` AND (`unguided_lab` or `ctf`) AND `retest` | `MASTERED` |
  | most recent `assessment`/`retest` failed, after previously reaching `ASSESSED`+ | `NEEDS_REVIEW` |

## Why

This directly encodes the "Prove Your Skill" matrix from the product spec:
completing a lesson can only ever reach `LEARNING`; independent, unguided
demonstration (an unguided lab or a CTF solve, not a walkthrough) is
required to reach `DEMONSTRATED`; and `MASTERED` requires a passed formal
assessment *and* independent demonstration *and* a retest, so it reflects
repeated, verified performance rather than a single lucky attempt. A
regression after mastery (a failed retest) is explicitly modeled as
`NEEDS_REVIEW` rather than silently staying `MASTERED`.

`occurred_at` alone is not a reliable "most recent evidence" ordering
signal, because Postgres' `now()` returns the same value for every
statement within one transaction — a grading pipeline that records several
evidence rows in one transaction (e.g. a retest immediately following an
assessment) can produce identical timestamps. A monotonic `seq` column
(`GENERATED ALWAYS AS IDENTITY`) is used as the real ordering tiebreaker.
This was caught by the regression suite, not assumed correct: see the git
history of `supabase/migrations/20260921000006_skill_graph.sql`.

## Consequences

- Any new way for a user to demonstrate a skill (a new lab type, a new
  assessment format) must go through a `SECURITY DEFINER` grading function
  that calls `record_skill_evidence()` after verifying the outcome itself.
  It must never let the client directly report `outcome = 'passed'`.
- `supabase/tests/002_skill_graph.sql` and
  `supabase/tests/003_grading_pipeline.sql` are the executable spec for
  this state machine — any change to the rules above must update those
  tests, not just the SQL comment.
