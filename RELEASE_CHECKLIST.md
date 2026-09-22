# Release Checklist

`[x]` = verified (there is a passing automated test, or it was manually
exercised and confirmed in this session). `[ ]` = not done, or not yet
verified even if code exists. Nothing here is marked `[x]` on assumption.

## Application foundation

- [x] Monorepo scaffolded (`apps/web`, `supabase/`, `scripts/`, `docs/`)
- [x] Next.js 16 App Router + TypeScript (strict) + Tailwind, builds clean
- [x] ESLint clean, `tsc --noEmit` clean
- [x] Design tokens (light + dark) established
- [x] Pushed to GitHub (`main`, commit history from `3a3eaba`)
- [ ] Flutter mobile app scaffolded (not started)
- [ ] i18n framework in place (not started)
- [ ] PWA / offline support (not started)

## Authentication

- [x] Sign up (Supabase Auth, server action, zod-validated password policy)
- [x] Log in
- [x] Log out
- [x] Password reset request + update
- [x] Email verification flow (confirmation link + `/verify-email` page)
- [x] OAuth/email confirmation callback route
- [x] Session refresh via proxy (middleware), auth wall on protected routes
- [x] e2e-tested: unauthenticated visitors are redirected from
      `/dashboard`, `/skills`, `/settings`, `/admin`, `/learn`, `/labs`,
      `/ctf`, `/mentor`
- [ ] MFA
- [ ] Application-layer rate limiting on auth endpoints (beyond Supabase's
      built-in limits)
- [ ] CAPTCHA/bot protection on signup

## Authorization / RBAC

- [x] Platform roles (user/instructor/moderator/admin) — schema + RLS
- [x] Organization-scoped roles (member/instructor/team_owner/org_admin) — schema + RLS
- [x] Privilege escalation prevention — **explicit regression test**
      (`supabase/tests/001_identity_rls.sql`): a user cannot self-grant a
      role, cannot escalate via UPDATE, cannot read another user's role rows
- [x] Server-side role check helpers (`requireUser`/`requireRole`/`requireAdmin`)
      used by protected routes, not just middleware redirects
- [x] Admin nav link only rendered for actual admins; `/admin` itself
      re-verifies via `requireAdmin()`, independent of the link
- [ ] Admin UI for granting/revoking *other users'* roles (an admin can
      author content; there is no UI yet to promote another user to
      instructor/moderator/admin — only directly in the database)

## Database / Security Rules

- [x] Every table has RLS enabled and `FORCE ROW LEVEL SECURITY`
- [x] 57 SQL regression assertions passing against a real Postgres instance
      (`bash scripts/run-sql-tests.sh`), covering identity/RBAC, skill graph,
      grading pipeline, entitlements, and a full seeded-content walkthrough
- [x] Audit log is append-only and unforgeable (verified by test)
- [x] 8 real bugs found and fixed during development, each with a regression
      test — see `SECURITY_AUDIT.md` (AUDIT-001 through AUDIT-008)
- [ ] Migrations applied to a real (non-local-test) Supabase project — see
      `MANUAL_SETUP.md` §2b (requires your Supabase project)
- [ ] Firestore — N/A (Supabase chosen, see ADR 0001)
- [ ] Storage bucket policies (no storage buckets defined yet — no file
      upload feature built yet)

## Skill Graph

- [x] Schema: skills, categories, prerequisites, evidence, derived state
- [x] State machine implemented and tested for all 7 states
      (`supabase/tests/002_skill_graph.sql`)
- [x] Evidence unforgeable by client (no INSERT grant; grading-function-only writes)
- [x] Real skill catalog seeded (38 skills, 8 categories)
- [x] `/skills` page renders real per-user state from the database
- [x] Proven end-to-end with real content: a seeded lesson + quiz + guided
      lab + CTF challenge genuinely advance a skill from `NOT_STARTED` to
      `DEMONSTRATED` (`supabase/tests/005_seeded_content_e2e.sql`)
- [ ] "Prove Your Skill" matrix UI (per-skill breakdown of theory/quiz/
      guided/unguided/CTF/assessment/remediation/retest) — data model
      supports it; UI not built

## Grading pipeline

- [x] `submit_quiz_attempt()` — grades server-side against hidden answer key
- [x] `submit_lab_flag()` — verifies hashed flag server-side, updates lab
      progress, records evidence, prevents cross-user submission
- [x] `submit_ctf_flag()` — hashed flag verification, anti-cheat unique
      constraint, idempotent resubmission
- [x] `unlock_lab_hint()` — records a hint unlock for the caller's own lab instance
- [x] End-to-end tested (`supabase/tests/003_grading_pipeline.sql`,
      `supabase/tests/005_seeded_content_e2e.sql`)
- [x] Wired to real learner-facing UI (`/learn/.../[lessonId]` embeds a live
      quiz; `/labs/[labId]` and `/ctf/[challengeId]` submit flags directly)

## Entitlements / Billing

- [x] Plan catalog + flexible per-plan entitlements schema
- [x] Every new user auto-enrolled on `free` plan with real limits
- [x] `get_entitlement()` / `set_active_subscription()` — server-side only,
      tested against self-escalation attempts
- [x] Webhook replay protection (unique constraint, tested)
- [ ] Live payment provider connected (deferred by design — ADR 0005)
- [ ] Billing UI (plan comparison/upgrade page)

## Content authoring (Admin CMS)

- [x] Learning paths, modules, lessons — full CRUD, markdown content editor,
      publish/draft toggle at every level, per-lesson skill tagging
- [x] Labs — CRUD, skill tagging, leveled hints, flags (hashed server-side,
      plaintext never stored/logged)
- [x] Quizzes — CRUD, skill tagging, question/choice builder with
      mark-correct checkboxes
- [x] CTF challenges — CRUD, skill tagging, same server-side flag hashing
- [x] One complete real content path seeded end-to-end (SQL injection: path
      → module → lesson → quiz → guided lab → CTF challenge), not a stub —
      see `supabase/migrations/20260921000014_seed_sample_content.sql`
- [ ] Announcements, translations (not built — section 29's full content
      type list is broader than what's built)
- [ ] Bulk import/export of content

## Learner-facing UI

- [x] `/learn` — published paths, real markdown lesson rendering
      (react-markdown), lesson-read tracking, embedded live quiz per lesson
- [x] `/labs` — published labs, guided/unguided start flow, hint unlocking,
      real flag submission and grading
- [x] `/ctf` — published challenges (via the flag-hash-free public view),
      real flag submission and grading, solved state persists
- [x] Every one of the above uses live Supabase queries/RPCs — no mock data
- [ ] Labs' actual sandboxed target environment is not provisioned (see
      "Labs / Terminal / Cyber Range" below) — clearly labeled in the UI

## Labs / Terminal / Cyber Range

- [x] Lab bookkeeping (instances, hints, flags, progress) — real, tested
- [ ] Lab engine runtime: no provisioning/execution engine for an actual
      sandboxed target exists yet. `/labs/[labId]` explicitly labels this
      rather than implying a live environment.
- [ ] Terminal simulator (not started)
- [ ] Cyber Range interconnected environments (not started)

## OSINT / Forensics / Blue-Purple Team

- [ ] Investigation workspace (not started)
- [ ] Blue/Purple Team scenario linkage (not started)

## CTF / Arena / Exams / Capstones

- [x] Schema + grading + anti-cheat constraint for CTF challenges
- [x] Admin CMS + learner UI for CTF challenges (see above)
- [x] Exam mode modeled via `quizzes.is_exam` (ADR 0004) — schema/grading
      only, no dedicated exam-mode UI (timer, restricted hints) yet
- [x] Capstone schema with staff-reviewed report submissions
- [ ] Arena/mission UI, timers, leaderboard (not started)
- [ ] Capstone submission/review UI (schema + RLS only)

## AI Security Mentor / AI-assisted scanning

- [x] `/mentor` chat UI (mode selector: Explain/Hint/Teach/Analyze Failure;
      conversation history; daily quota display)
- [x] `POST /api/mentor/chat` — real Anthropic API calls (model
      `claude-sonnet-5`), grounded only in real, server-fetched Skill Graph
      data (never client-asserted) — see ADR 0007
- [x] Rate limiting via the real entitlement engine
      (`ai_mentor_daily_requests`), not a separate ad hoc limiter
- [x] Structural (not just prompted) guarantee that the Mentor cannot write
      skill_evidence/user_skill_states — no INSERT grant exists for the
      Mentor's code path, matching the grading pipeline's own design
- [x] System prompt separates SYSTEM INSTRUCTIONS / mode instructions /
      TRUSTED APPLICATION DATA from the untrusted user message (passed as a
      separate API turn, never concatenated into the system prompt) — unit
      tested (`lib/mentor/__tests__/prompt.test.ts`, 15 assertions)
- [x] "Ask Mentor" entry points from lab, lesson, and CTF challenge pages
- [x] Only unlocked lab hints are ever included in context; flags are never
      queried by any Mentor code path
- [ ] Not implemented: EXPLAIN_FINDING / REVIEW_REPORT / REVIEW_METHODOLOGY
      modes are wired into the API/UI but honestly tell the user those
      platform features (scanner, reports) don't exist yet, rather than
      inventing content — real implementation waits on the scanner/reports
      phases
- [ ] AI-assisted reasoning layer for the security scanner (waits on the
      scanner itself, not started)
- [ ] Response streaming (current implementation is request/response, not
      token-by-token)

## Security scanning engine

- [ ] Not started.

## Reports

- [ ] Not started.

## Admin / Instructor / Teams

- [x] Organizations + org-scoped roles (schema + RLS)
- [x] Admin CMS UI (learning paths/modules/lessons/labs/quizzes/CTF — see above)
- [ ] Instructor dashboard (view org members' progress) — RLS supports it
      (`skill_evidence`/`user_skill_states`/`lab_progress` policies already
      grant instructor visibility); no UI built
- [ ] Team management UI (invite members, assign org roles) — schema + RLS
      only

## Privacy / Data protection

- [x] Account data model supports deletion via `auth.users` cascade (every
      user-owned table has `ON DELETE CASCADE` to `auth.users.id`)
- [ ] User-facing "delete my account" flow (not built)
- [ ] User-facing data export (not built)
- [ ] Documented retention policy (not written)

## Logging / Auditing

- [x] Append-only audit log, server-attributed, admin/org-admin readable only
- [ ] Audit events wired into every section-34 action (only
      `quiz.attempt.submitted`, `lab.flag.submitted`, `ctf.flag.submitted`,
      `subscription.changed` currently log — login/role-change/etc. not
      yet instrumented from application code)

## CI/CD

- [x] Lint, typecheck, unit tests, production build, DB+RLS regression
      tests, secret scan, dependency audit, e2e smoke tests — all running
      in GitHub Actions (`.github/workflows/ci.yml`)
- [x] All of the above verified passing locally before every commit
- [x] Pushed to GitHub — Claude GitHub App access was granted mid-session
      (previously blocked; see git history for the resolution)
- [ ] Actually observed green on a real GitHub Actions run (verify by
      checking the Actions tab on the repository)
- [ ] Deploy job (no hosting target connected yet — see `MANUAL_SETUP.md` §5)

## Testing

- [x] 57 SQL regression assertions (RLS + grading + entitlements + a full
      seeded-content walkthrough)
- [x] 41 unit tests (validation logic, env guards, UI component, AI Mentor prompt safety)
- [x] 13 e2e smoke tests (public pages, auth wall across all protected
      sections, login error handling)
- [ ] Test coverage for admin CMS CRUD flows (built and manually verified
      via typecheck/lint/build; no dedicated e2e tests exercising the forms
      themselves yet — would need a real Supabase project or a more
      elaborate local auth fixture than the current e2e setup has)
- [ ] Load/performance testing (not started)

## Production readiness

- [ ] Real Supabase project provisioned (`MANUAL_SETUP.md` §2)
- [ ] Deployment target connected (`MANUAL_SETUP.md` §5)
- [ ] Domain configured (`MANUAL_SETUP.md` §6, optional)
- [ ] Production environment variables set (`MANUAL_SETUP.md` §2a, §7)

## Mobile readiness

- [x] Backend contracts (Postgres schema + RPC functions) kept independent
      of Next.js-specific code, so a Flutter client can call the same
      Supabase project directly
- [ ] Flutter app itself (not started)
