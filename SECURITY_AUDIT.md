# Security Audit

This document records security-relevant findings discovered while building
iCorePen, honestly, including ones that were bugs in this session's own
work before they were fixed. It is updated as the build progresses through
further phases (security scanner, lab engine, terminal, OSINT workspace,
etc.) and as adversarial review is performed on each new feature.

Status legend: `FIXED` (found, root-caused, fixed, regression-tested),
`MITIGATED` (reduced risk, full fix pending), `ACCEPTED_GAP` (a real,
currently-absent control, tracked for a later phase), `INFORMATIONAL`.

---

## AUDIT-001 — Default privilege grant would have silently defeated function lockdown

- **Severity**: High (would have been, in a real deployment of this pattern)
- **Confidence**: Confirmed (reproduced and fixed)
- **Component**: Local test harness bootstrap (`supabase/tests/bootstrap/0000_auth_stub.sql`), by extension a warning for how *any* future migration grants privileges.
- **Description**: The test-harness bootstrap originally ran `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role`. This grants EXECUTE on every *future* function directly to `anon`/`authenticated` as an independent ACL entry. `record_skill_evidence()` and other sensitive `SECURITY DEFINER` functions then did `REVOKE ALL ... FROM public`, intending to lock the function down — but `REVOKE ... FROM public` only removes the PUBLIC-wide grant; it does **not** remove a grant made directly to a named role via default privileges. The revoke silently no-opped for `anon`/`authenticated`.
- **Evidence**: `supabase/tests/002_skill_graph.sql`'s "record_skill_evidence() is not callable by authenticated" test failed on first run with the function callable by a plain authenticated user — i.e., a user could have called it directly to fabricate skill mastery.
- **Impact**: If this pattern had shipped, any authenticated client could call `record_skill_evidence()` directly and insert arbitrary "passed" evidence for any skill, completely defeating the Skill Graph's core "no fake mastery" guarantee (see ADR 0003).
- **Root cause**: Vanilla Postgres already grants EXECUTE on new functions to `PUBLIC` by default (unlike tables/sequences, which need an explicit grant) — the extra default-privilege rule for functions was unnecessary and actively harmful, since it created a second, independent grant that `REVOKE ... FROM public` doesn't touch.
- **Fix**: Removed the `ALTER DEFAULT PRIVILEGES ... ON FUNCTIONS` line from the bootstrap entirely; rely on vanilla Postgres' PUBLIC-execute default plus explicit `REVOKE ALL ... FROM public` + `GRANT EXECUTE ... TO <specific role>` per sensitive function, exactly matching real Supabase project behavior.
- **Verification**: `supabase/tests/002_skill_graph.sql` and `supabase/tests/004_entitlements.sql` now pass, explicitly asserting these functions are not callable by `authenticated`.
- **Status**: `FIXED`.

## AUDIT-002 — Reserved SQLSTATE collided with generic exception handling

- **Severity**: Medium
- **Confidence**: Confirmed
- **Component**: `supabase/migrations/20260921000010_grading_and_evidence.sql` (`submit_lab_flag()`)
- **Description**: The function raised a custom "lab instance is not active" error using `ERRCODE = 'P0004'`. `P0004` is Postgres' reserved SQLSTATE for `assert_failure`, one of exactly two conditions (`query_canceled` and `assert_failure`) that a plain `EXCEPTION WHEN others THEN` handler does **not** catch.
- **Evidence**: A test wrapping a call to `submit_lab_flag()` in `EXCEPTION WHEN others THEN` to assert it was rejected instead saw the raw error escape uncaught and abort the script.
- **Impact**: Application code that reasonably wraps calls to this RPC in generic error handling would see the error propagate as an unhandled exception instead, likely surfacing as a raw 500 to the end user (an error-handling/UX defect, not a data-integrity one — the operation itself was still correctly rejected).
- **Root cause**: Reuse of a Postgres-reserved SQLSTATE for an application-level error code.
- **Fix**: Changed to `P0005` (undefined by Postgres, safe for application use) and documented the collision inline so it isn't reintroduced.
- **Verification**: `supabase/tests/003_grading_pipeline.sql`, "cannot submit against a stopped lab instance" test.
- **Status**: `FIXED`.

## AUDIT-003 — CTF flag resubmission could crash on a unique constraint

- **Severity**: Low (availability/correctness, not a security bypass)
- **Confidence**: Confirmed
- **Component**: `submit_ctf_flag()`
- **Description**: A user resubmitting an already-correct flag (e.g. double-clicking submit) hit the partial unique index `ctf_submissions_one_correct_per_user`, since the original logic always inserted a new row on a correct guess.
- **Impact**: A legitimate, harmless action (resubmitting a flag you already solved) would throw a database error instead of behaving predictably. Not an authorization bypass — the anti-cheat constraint itself held.
- **Root cause**: Missing idempotency handling for the "already solved, guessed correctly again" case.
- **Fix**: The function now returns the original scoring submission unchanged when the challenge is already solved, instead of attempting a second insert.
- **Verification**: `supabase/tests/003_grading_pipeline.sql`, "CTF flag awards points once, resubmission does not double-award" test.
- **Status**: `FIXED`.

## AUDIT-004 — Evidence ordering relied on a non-unique timestamp

- **Severity**: Medium (skill-state integrity)
- **Confidence**: Confirmed
- **Component**: `public.recompute_skill_state()`
- **Description**: "Most recent assessment/retest outcome" was determined via `ORDER BY occurred_at DESC`. Postgres' `now()` returns the same value for every statement inside one transaction, so multiple evidence rows recorded in a single transaction (e.g. a grading pipeline that records an assessment and a retest together) could tie on `occurred_at`, making "most recent" non-deterministic.
- **Evidence**: A test asserting a failed retest immediately after mastery produces `NEEDS_REVIEW` initially returned `MASTERED` instead.
- **Impact**: A skill could remain shown as `MASTERED` after a failed retest that should have flagged it `NEEDS_REVIEW`, undermining the accuracy the Skill Graph promises.
- **Root cause**: Ordering by a non-unique, transaction-scoped timestamp.
- **Fix**: Added a monotonic `seq bigint GENERATED ALWAYS AS IDENTITY` column to `skill_evidence` and order by `(occurred_at, seq) DESC`.
- **Verification**: `supabase/tests/002_skill_graph.sql`, full state-machine transition test sequence.
- **Status**: `FIXED`.

## AUDIT-005 — Invalid `<button>` nested inside `<a>` on the landing page

- **Severity**: Low (accessibility/HTML validity, not a security issue)
- **Confidence**: Confirmed
- **Component**: `apps/web/src/app/page.tsx`
- **Description**: CTA links were built as `<Link href="..."><Button>...</Button></Link>`, rendering a `<button>` nested inside an `<a>` — invalid HTML5 (interactive content cannot nest) with inconsistent assistive-technology behavior.
- **Evidence**: Caught by a Playwright e2e assertion (`getByRole('link', { name: 'Log in' })` resolved ambiguously) while writing the e2e smoke suite.
- **Impact**: Degraded screen-reader/accessibility behavior; not a security vulnerability.
- **Fix**: Introduced `ButtonLink`, rendering a single `<a>` styled like a button, replacing every `Link`-wrapping-`Button` usage.
- **Verification**: `apps/web/e2e/smoke.spec.ts` passes; manual DOM inspection confirms no nested interactive elements remain.
- **Status**: `FIXED`.

---

## Verified controls (tested, not just asserted)

- **service_role key cannot reach the client bundle**: confirmed by
  intentionally importing `lib/supabase/admin.ts` from a Client Component
  and observing `next build` hard-fail with `server-only`'s error, both
  for the browser bundle and the SSR bundle. Test route removed after
  verification (not present in the committed tree).
- **Privilege escalation prevention**: `supabase/tests/001_identity_rls.sql`
  proves a user cannot self-grant a role, cannot escalate via UPDATE,
  cannot read another user's role rows, and cannot forge an audit log entry.
- **Entitlement bypass prevention**: `supabase/tests/004_entitlements.sql`
  proves a user cannot insert/modify their own subscription and that
  `set_active_subscription()` itself refuses non-admin/non-service callers
  even if RLS were somehow bypassed (defense in depth).
- **Skill mastery cannot be fabricated**: `supabase/tests/002_skill_graph.sql`
  and `003_grading_pipeline.sql` prove evidence can only be written by
  grading functions that independently verify the outcome, and that wrong
  answers/flags are correctly rejected without granting progress.

## Known, currently-accepted gaps (not yet implemented)

These are real absences, not oversights being hidden — tracked here and in
`RELEASE_CHECKLIST.md` so they aren't lost.

- **ACCEPTED_GAP**: No application-layer rate limiting yet on auth endpoints
  (signup, login, password reset) beyond Supabase Auth's own built-in
  limits. Section 32 of the product spec requires this; not yet built.
- **ACCEPTED_GAP**: No MFA implementation yet.
- **ACCEPTED_GAP**: No CAPTCHA/bot protection on signup.
- **ACCEPTED_GAP**: Live payment provider not connected (by explicit
  product decision — see ADR 0005); all current plan grants are
  admin/`service_role` actions.
- **ACCEPTED_GAP**: No admin CMS UI yet to author lessons/labs/CTF content
  — the schema and grading functions exist and are tested, but nothing is
  seeded beyond the skill catalog, so there is no learner-facing content to
  exploit or protect yet.
- **INFORMATIONAL**: `pnpm audit --prod --audit-level=high` reports no
  known vulnerabilities as of this writing, but `continue-on-error: true`
  in CI means a future finding won't fail the build automatically — it's
  advisory until someone reviews and either fixes or explicitly
  acknowledges it.
