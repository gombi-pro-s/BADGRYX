# Release Checklist

`[x]` = verified (there is a passing automated test, or it was manually
exercised and confirmed in this session). `[ ]` = not done, or not yet
verified even if code exists. Nothing here is marked `[x]` on assumption.

## Application foundation

- [x] Monorepo scaffolded (`apps/web`, `supabase/`, `scripts/`, `docs/`)
- [x] Next.js 16 App Router + TypeScript (strict) + Tailwind, builds clean
- [x] ESLint clean, `tsc --noEmit` clean
- [x] Design tokens (light + dark) established
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
      `/dashboard`, `/skills`, `/settings`, `/admin`
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
- [ ] Admin UI for granting/revoking roles (schema supports it; no UI yet)

## Database / Security Rules

- [x] Every table has RLS enabled and `FORCE ROW LEVEL SECURITY`
- [x] 46 SQL regression assertions passing against a real Postgres instance
      (`bash scripts/run-sql-tests.sh`), covering identity/RBAC, skill graph,
      grading pipeline, and entitlements
- [x] Audit log is append-only and unforgeable (verified by test)
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
- [ ] "Prove Your Skill" matrix UI (per-skill breakdown of theory/quiz/
      guided/unguided/CTF/assessment/remediation/retest) — data model
      supports it; UI not built

## Grading pipeline

- [x] `submit_quiz_attempt()` — grades server-side against hidden answer key
- [x] `submit_lab_flag()` — verifies hashed flag server-side, updates lab
      progress, records evidence, prevents cross-user submission
- [x] `submit_ctf_flag()` — hashed flag verification, anti-cheat unique
      constraint, idempotent resubmission
- [x] End-to-end tested (`supabase/tests/003_grading_pipeline.sql`)
- [ ] No UI wired to these yet — no lessons/labs/CTF content authored/seeded

## Entitlements / Billing

- [x] Plan catalog + flexible per-plan entitlements schema
- [x] Every new user auto-enrolled on `free` plan with real limits
- [x] `get_entitlement()` / `set_active_subscription()` — server-side only,
      tested against self-escalation attempts
- [x] Webhook replay protection (unique constraint, tested)
- [ ] Live payment provider connected (deferred by design — ADR 0005)
- [ ] Billing UI (plan comparison/upgrade page)

## Labs / Terminal / Cyber Range

- [ ] Lab engine runtime (schema exists; no provisioning/execution engine built)
- [ ] Terminal simulator (not started)
- [ ] Cyber Range interconnected environments (not started)

## OSINT / Forensics / Blue-Purple Team

- [ ] Investigation workspace (not started)
- [ ] Blue/Purple Team scenario linkage (not started)

## CTF / Arena / Exams / Capstones

- [x] Schema + grading + anti-cheat constraint for CTF challenges
- [x] Exam mode modeled via `quizzes.is_exam` (ADR 0004)
- [x] Capstone schema with staff-reviewed report submissions
- [ ] Arena/mission UI, timers, leaderboard (not started)
- [ ] Any actual lab/CTF/exam/capstone content authored (none seeded)

## AI Security Mentor / AI-assisted scanning

- [ ] Not started. `ANTHROPIC_API_KEY` reserved in `.env.example` but no
      code path uses it yet.

## Security scanning engine

- [ ] Not started.

## Reports

- [ ] Not started.

## Admin / Instructor / Teams

- [x] Organizations + org-scoped roles (schema + RLS)
- [ ] Admin CMS UI (lessons/modules/paths/labs/challenges/hints/etc.)
- [ ] Instructor dashboard (view org members' progress) — RLS supports it
      (`skill_evidence`/`user_skill_states`/`lab_progress` policies already
      grant instructor visibility); no UI built

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
- [x] All of the above verified passing locally before being committed
- [ ] Verified green on an actual GitHub Actions run (blocked: this
      session cannot push — see `MANUAL_SETUP.md` §1)
- [ ] Deploy job (no hosting target connected yet — see `MANUAL_SETUP.md` §5)

## Testing

- [x] 46 SQL regression assertions (RLS + grading + entitlements)
- [x] 26 unit tests (validation logic, env guards, UI component)
- [x] 9 e2e smoke tests (public pages, auth wall, login error handling)
- [ ] Test coverage for content model CRUD (no admin UI exists yet to test)
- [ ] Load/performance testing (not started)

## Production readiness

- [ ] Real Supabase project provisioned (`MANUAL_SETUP.md` §2)
- [ ] Deployment target connected (`MANUAL_SETUP.md` §5)
- [ ] Domain configured (`MANUAL_SETUP.md` §6, optional)
- [ ] Production environment variables set (`MANUAL_SETUP.md` §2a, §7)
- [ ] This work pushed to GitHub (blocked — `MANUAL_SETUP.md` §1)

## Mobile readiness

- [x] Backend contracts (Postgres schema + RPC functions) kept independent
      of Next.js-specific code, so a Flutter client can call the same
      Supabase project directly
- [ ] Flutter app itself (not started)
