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

## AUDIT-006 — `REVOKE SELECT` on `ctf_challenges` blocked admins, not just non-staff

- **Severity**: Medium (broke intended admin functionality; not an authorization bypass in the other direction)
- **Confidence**: Confirmed
- **Component**: `supabase/migrations/20260921000009_content_model_rls.sql`
- **Description**: To keep `flag_hash` away from non-staff users, the migration ran `REVOKE SELECT ON public.ctf_challenges FROM anon, authenticated`, reasoning that RLS is row-level and can't hide a single column. That reasoning was correct but the fix was wrong: `authenticated` is one shared Postgres role for every logged-in user, admins included — Postgres role-level GRANT/REVOKE has no concept of "admin" within that role. Revoking SELECT from `authenticated` blocked every authenticated request against the table, including an admin's own, regardless of what the RLS policy said.
- **Evidence**: While building the admin CMS for CTF challenge management, a test asserting an admin can read `ctf_challenges` directly (needed to list/edit challenges) failed with a permission-denied error.
- **Impact**: Admins could not manage CTF challenges through their own authenticated session at all — the base table was unreadable to every logged-in role, not just non-staff. (Not an authorization bypass: the direction of the bug was over-restrictive, not under-restrictive — no evidence flag_hash was ever exposed to non-staff.)
- **Root cause**: Conflating "hide a column from some rows" (which RLS genuinely cannot do) with this table's actual policy shape ("staff sees the full row, everyone else sees no row at all") — which RLS's `is_staff()` policy already handles completely correctly on its own, making the REVOKE both unnecessary and harmful.
- **Fix**: Removed the `REVOKE SELECT` statement; the `ctf_challenges_staff_only` RLS policy alone now governs access (non-staff get zero rows via RLS, staff get full rows including `flag_hash`).
- **Verification**: `supabase/tests/003_grading_pipeline.sql` now has both directions covered: non-staff sees zero rows (not an error), and a separate test confirms an admin can read the row including a well-formed `flag_hash` directly.
- **Status**: `FIXED`.

## AUDIT-007 — `tsc --noEmit` depended on stale build artifacts, would have broken CI on a fresh checkout

- **Severity**: Low (build/CI reliability, not a security issue)
- **Confidence**: Confirmed
- **Component**: `apps/web/src/app/layout.tsx`
- **Description**: The root layout used create-next-app's generated `LayoutProps<"/">` type, an ambient type declared in `.next/types/**/*.ts` — generated only by running `next dev` or `next build` first. `.next/` is (correctly) gitignored. `pnpm typecheck` passed locally only because a `.next` directory from earlier manual `pnpm build`/`pnpm dev` runs in this sandbox was still present; the moment it was removed (as it should be for a clean checkout, and as CI's `lint-typecheck` job — which runs `tsc --noEmit` without building first — would experience on every run), typecheck failed with `Cannot find name 'LayoutProps'`.
- **Evidence**: Reproduced by deleting `.next` and rerunning `pnpm typecheck`, which failed; every other layout file in the app already used a plain `{ children: React.ReactNode }` prop type and was unaffected.
- **Impact**: The `lint-typecheck` CI job would have failed on every run (it checks out a fresh clone with no `.next` directory), even though the code was otherwise correct — a false-negative CI failure blocking all future PRs until diagnosed.
- **Root cause**: Relying on a generated ambient type in a file that typecheck must be able to validate standalone, without assuming a prior build step ran first.
- **Fix**: Changed `RootLayout`'s prop type to `{ children: React.ReactNode }`, matching every other layout in the codebase.
- **Verification**: Removed `.next` entirely and reran `pnpm typecheck` — passes clean.
- **Status**: `FIXED`.

## AUDIT-008 — `interface` Row types silently collapsed all Supabase query results to `never`

- **Severity**: Low (type-safety/build correctness, not a runtime security issue — but see impact)
- **Confidence**: Confirmed via isolated minimal reproduction
- **Component**: `apps/web/src/types/database.ts`
- **Description**: While expanding the hand-written `Database` type to cover the content model tables for the admin CMS, every query in the app (including pre-existing, previously-working ones like `profiles`) started typechecking as `never`, with no error pointing at a specific cause. Bisection down to a ~15-line reproduction found the exact trigger: declaring a multi-field Row type as `export interface ProfileRow {...}` and referencing it as `Row: ProfileRow` breaks `@supabase/postgrest-js`'s generic result inference for the *entire* `Database` type, not just that table. Changing only the declaration to `export type ProfileRow = {...}` (a type alias, structurally identical) fixed it completely, with no other change.
- **Evidence**: `apps/web/src/types/database.ts`'s file header documents the isolated repro; git history shows the single-keyword change (`interface` → `type`) that fixed 24 simultaneous, seemingly unrelated typecheck errors.
- **Impact**: This is a correctness/reliability finding, not an exploitable vulnerability — but it's exactly the kind of silent failure the "no half-finished implementations" and "don't claim something works without verifying" rules exist to catch: every Row type on every table would have typechecked as `never`, meaning TypeScript would silently stop catching real mistakes (wrong column names, wrong types) in any code touching the database, while still reporting *some* unrelated-looking errors that could mislead a developer into fixing the wrong thing.
- **Root cause**: An apparent interaction between TypeScript's handling of `interface` vs `type` alias references inside deeply nested conditional/mapped types, specific to this combination of TypeScript and `@supabase/postgrest-js` versions.
- **Fix**: Every Row type in `database.ts` uses `type X = {...}`, never `interface`. Documented prominently in the file header as a trap for future contributors.
- **Verification**: `pnpm typecheck` clean after the change; isolated repro retained in the commit history/PR discussion for anyone who doubts it.
- **Status**: `FIXED`.

## AUDIT-009 — `/api/mentor/chat`'s context-type allowlist fell behind the UI's, breaking two just-added "Ask Mentor" deep links

- **Severity**: Medium (a real, user-facing functional break, not a data-exposure issue)
- **Confidence**: Confirmed (found by re-reading the route immediately after adding the second new context type, before any user could hit it)
- **Component**: `apps/web/src/app/api/mentor/chat/route.ts`
- **Description**: `/mentor`'s own page component validates its `?contextType=` search param against one hand-written array; `POST /api/mentor/chat`'s zod request schema validated `contextType` against a second, separately hand-written array. When `'investigation'` and then `'finding'` were added to `MentorContextType` (two consecutive phases this session), both were added to the page's array and to `buildFocusDetail()`, but the API route's copy was missed entirely.
- **Evidence**: Found by re-reading `route.ts` right after the `'finding'` addition landed — `CONTEXT_TYPES` there still read `["skill", "lesson", "lab", "ctf", "general"]`.
- **Impact**: Every "Ask Mentor" link added for investigations and scanner findings would render the `/mentor` page correctly (the page's own array was right) but fail the moment the user sent an actual message — `zod`'s `.enum()` would reject `contextType: "investigation"`/`"finding"` with a 400 "Invalid request," making both brand-new deep links functionally broken end to end despite compiling and rendering cleanly.
- **Root cause**: The same logical constant (every valid `MentorContextType`) was duplicated across two files with no shared source of truth, so adding a new context type required remembering to update both — an easy step to miss, and nothing (not `tsc`, not lint, not the existing test suite) would have caught the drift.
- **Fix**: Both arrays replaced with one exported constant, `ALL_MENTOR_CONTEXT_TYPES` (`apps/web/src/lib/mentor/context.ts`), imported by both `/mentor/page.tsx` and the chat route. A third context type can now only be added correctly, not incorrectly-in-one-place.
- **Verification**: `tsc --noEmit` clean; manually traced both call sites to confirm they now import the same constant.
- **Status**: `FIXED`.

## AUDIT-010 — `subscriptions.subject_id` has no real foreign key, so deleting a user or organization orphaned their subscription row forever

- **Severity**: Medium (data-integrity/privacy hygiene, not an access-control break — an orphaned row was never readable by anyone once its subject was gone, RLS on `subscriptions` is subject-scoped)
- **Confidence**: Confirmed by direct reproduction against the local test DB
- **Component**: `public.subscriptions` (`supabase/migrations/20260921000011_entitlements.sql`)
- **Description**: `subscriptions.subject_id` is deliberately polymorphic — it holds either an `auth.users.id` or an `organizations.id` depending on `subject_type`, so it structurally cannot carry a normal single-table foreign key. ADR 0012's account-deletion work fixed all 8 *attribution* columns referencing `auth.users` (`granted_by`, `created_by`, etc.), but `subject_id` is neither of ADR 0012's two categories — it's not attribution, and it has no FK at all to be missing an `ON DELETE` clause on. That combination meant nothing was checking it.
- **Evidence**: Reproduced directly: inserted a real `subscriptions` row for a test user (`subject_type = 'user'`), deleted that user from `auth.users`, then queried `subscriptions WHERE subject_id = <the deleted id>` — the row was still there, `DELETE FROM auth.users` succeeded with no error (nothing to violate), and nothing cleaned it up.
- **Impact**: Every deleted user's (and every deleted organization's) subscription history would accumulate permanently as orphaned rows referencing a subject that no longer exists — silent data hygiene rot, not immediately visible in any UI (RLS already made these rows unreadable by anyone once the subject was gone) but a real, growing correctness gap in the schema, and exactly the kind of thing `SELECT * FROM subscriptions` on the Supabase dashboard would eventually surface as confusing.
- **Root cause**: A polymorphic reference column, by definition, can't use a normal `REFERENCES` constraint — the schema needs an explicit substitute (a trigger) for what a real FK would otherwise enforce, and none was added when `subscriptions` was designed.
- **Fix**: Two `AFTER DELETE` triggers (`supabase/migrations/20260922000023_subscription_cleanup_on_delete.sql`) on `auth.users` and `public.organizations`, each deleting matching `subscriptions` rows for that subject — mirroring the `AFTER INSERT` triggers that already exist on both tables for the opposite direction (`handle_new_user_free_plan`, `handle_new_organization`). Deletion (not nulling) is correct here because `subject_id` is ownership, not attribution — the row's entire reason to exist is that specific user or organization.
- **Verification**: `supabase/tests/021_subscription_cleanup_on_delete.sql` — deleting a user with a real (trigger-created) free-plan subscription removes exactly that row, leaves a different user's and an unrelated organization's subscriptions untouched, and deleting an organization removes its own subscription row too.
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
