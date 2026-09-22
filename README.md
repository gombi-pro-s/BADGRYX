# iCorePen

A cybersecurity learning, security-analysis, cyber-range, CTF, OSINT,
defensive-security, and AI-assisted security platform. The core philosophy:
**learn → investigate → enumerate → practice → analyze → validate → exploit
in controlled labs → collect evidence → document → remediate → retest →
prove skill → master.**

This is not a tutorial site. The platform tracks a [Skill Graph](#skill-graph)
of demonstrated ability, backed by real evidence (quizzes graded server-side,
lab flags verified server-side, CTF challenges, assessments, retests) —
never by "a lesson was opened."

## Status

This repository is under active, phased construction. See
[`RELEASE_CHECKLIST.md`](./RELEASE_CHECKLIST.md) for exactly what is real and
verified today versus what is still planned, and
[`SECURITY_AUDIT.md`](./SECURITY_AUDIT.md) for findings from the ongoing
security review. Do not assume a feature exists because it's described in
product vision docs — only what's in this README's
["What actually works today"](#what-actually-works-today) section and the
release checklist is real.

## Architecture

```
apps/
  web/                Next.js 16 (App Router, TypeScript, Tailwind) — the web app
mobile/                Flutter/Dart mobile app (planned; consumes the same Supabase backend)
supabase/
  migrations/          Every schema change, as plain numbered SQL files
  tests/               SQL regression tests exercising RLS policies and grading logic for real
  config.toml          Supabase CLI project config
scripts/
  local-test-db.sh      Rebuilds a local Postgres DB that stands in for a Supabase project
  run-sql-tests.sh       Applies migrations + runs every supabase/tests/*.sql file
.github/workflows/ci.yml All CI: lint, typecheck, unit tests, build, DB+RLS tests, security scan, e2e
docs/adr/               Engineering Decision Records for significant architecture choices
```

**Backend**: Supabase (Postgres + Row Level Security + Auth). See
[`docs/adr/0001-supabase-over-firebase.md`](./docs/adr/0001-supabase-over-firebase.md)
for why. Authorization is enforced **server-side** via RLS policies and
`SECURITY DEFINER` functions — never trust a client-side role check alone.

**Frontend**: Next.js App Router for web; Flutter/Dart planned for mobile,
sharing the same Supabase backend and (future) API routes. Business logic
that both clients need lives in the database (RLS + functions) or in Next.js
Route Handlers, not inside React components, so the Flutter app can use it
too.

**AI provider**: Anthropic Claude. Powers the AI Security Mentor (`/mentor`)
today; the AI-assisted reasoning layer of the security scanner will reuse
the same key once that phase is built. See
[`docs/adr/0007-ai-mentor-grounding.md`](./docs/adr/0007-ai-mentor-grounding.md)
for how it stays grounded in real data and cannot fabricate progress.

**Billing**: entitlement engine is real and enforced server-side now
(`plans`, `subscriptions`, `get_entitlement()`); a live payment provider
(Stripe/Paystack/Flutterwave) is deliberately not connected yet. See
[`docs/adr/0005-entitlements-before-billing.md`](./docs/adr/0005-entitlements-before-billing.md).

## What actually works today

- **Auth**: sign up, log in, log out, password reset, email verification,
  session refresh — all real, via Supabase Auth.
- **RBAC**: platform roles (user/instructor/moderator/admin) and
  organization-scoped roles (member/instructor/team_owner/org_admin),
  enforced by RLS. A user can never self-escalate — this is covered by an
  explicit regression test, not just a design intent.
- **Skill Graph**: real skill catalog (38 skills across 8 categories), a
  documented state machine (`NOT_STARTED` → ... → `MASTERED` /
  `NEEDS_REVIEW`), computed server-side from evidence. Viewable at
  `/skills` once logged in.
- **Grading pipeline**: `submit_quiz_attempt()`, `submit_lab_flag()`,
  `submit_ctf_flag()` — each independently verifies the outcome server-side
  (hidden answer keys, hashed flags) before writing any skill evidence.
  Wired to real learner-facing UI (see below), not just callable via RPC.
- **Admin CMS**: full authoring UI at `/admin` for learning paths, modules,
  lessons (markdown), labs (hints + hashed flags), quizzes (question/choice
  builder), and CTF challenges — all enforced by the same staff-only RLS
  policies as everything else, not a service-role bypass.
- **Learner UI**: `/learn`, `/labs`, `/ctf` — real markdown lessons with
  embedded live quizzes, guided/unguided lab attempts with hint unlocking,
  and CTF flag submission, all backed by live queries/RPCs.
- **Lab terminal simulator**: labs with an authored environment get a real
  interactive terminal (`ls`/`cat`/`grep`/`sudo`/... against a virtual
  filesystem, with genuine Unix-style read permissions enforced). The
  environment's content, including any flag text, is never sent to the
  browser directly — only the output of a command the learner actually ran
  server-side. See
  [`docs/adr/0009-lab-terminal-server-side.md`](./docs/adr/0009-lab-terminal-server-side.md).
- **Real seeded content**: one complete path (SQL injection: lesson → quiz
  → guided lab → CTF challenge) proves the whole pipeline works end to end
  — a test user answers the real quiz, submits the real flags, and the
  `sql-injection` skill genuinely reaches `DEMONSTRATED`. A second seeded
  lab, "Linux Privilege Escalation: Misconfigured Sudo", proves the
  terminal simulator the same way — a real, well-known technique (an
  unrestricted sudo rule on `cat`), solvable only by actually running the
  right commands in the terminal, not by reading page source.
- **AI Security Mentor** (`/mentor`): real Anthropic API calls grounded
  only in the user's actual Skill Graph data — never fabricated, and
  structurally unable to write skill evidence (see ADR 0007). Rate-limited
  through the real entitlement engine.
- **Security scanner** (`/scanner`): a real deterministic static-analysis
  rule engine (12 rule modules — secrets, SQL injection, XSS, command
  injection, path traversal, insecure eval, weak crypto, insecure CORS,
  insecure cookies, cleartext HTTP, prototype pollution, unsafe
  deserialization) scans pasted or uploaded source, with an optional
  AI-enrichment step that can only improve a finding's explanation text,
  never invent or reclassify one (see ADR 0008). Each finding has a real,
  tested attack → fix → retest status lifecycle enforced server-side.
- **Entitlements**: every user gets a real `free` plan on signup with real
  limits; only an admin or `service_role` can change a subscription.
- **Audit log**: append-only, RLS-protected, written only via
  `log_audit_event()`.

## What is designed but not yet UI-wired

Capstone submissions and instructor dashboards have a complete schema and
RLS policies (an instructor can already see their org members' real
progress at the database level) but no UI yet. See
[`RELEASE_CHECKLIST.md`](./RELEASE_CHECKLIST.md) for the full, honestly
tracked list of what remains (security scanner, lab sandbox/terminal
engine, OSINT/forensics workspace, Blue/Purple Team scenarios, Cyber
Range, Arena/exam timers, live billing, mobile app, i18n, PWA).

## Local development

### Prerequisites

- Node.js 20+ and [pnpm](https://pnpm.io) (`corepack enable` will get you
  the right version automatically — see `packageManager` in `package.json`).
- A Supabase project (see [`MANUAL_SETUP.md`](./MANUAL_SETUP.md) for exact
  steps) **or** just Postgres for running the SQL test suite without a full
  Supabase project.

### Install

```bash
pnpm install
```

### Configure environment variables

```bash
cp apps/web/.env.example apps/web/.env.local
# fill in NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY,
# SUPABASE_SERVICE_ROLE_KEY -- see MANUAL_SETUP.md for exactly where to
# get each one.
```

### Apply the database schema

Against a real Supabase project, use the Supabase CLI:

```bash
pnpm dlx supabase login
pnpm dlx supabase link --project-ref <your-project-ref>
pnpm dlx supabase db push
```

Against a local Postgres instance (no Supabase project needed — this is
what CI and the SQL regression suite use):

```bash
bash scripts/run-sql-tests.sh
```

This rebuilds a scratch database with a stand-in `auth` schema and the
`anon`/`authenticated`/`service_role` Postgres roles, applies every
migration in order, and runs every file in `supabase/tests/` as a real,
role-switching regression test (not a syntax check) — see the comments in
`supabase/tests/bootstrap/0000_auth_stub.sql` for exactly what it does and
does not replicate about a real Supabase project.

### Run the web app

```bash
pnpm dev
# http://localhost:3000
```

### Tests

```bash
pnpm --filter @icorepen/web lint
pnpm --filter @icorepen/web typecheck
pnpm --filter @icorepen/web test        # unit tests (vitest)
pnpm --filter @icorepen/web test:e2e    # e2e smoke tests (playwright)
bash scripts/run-sql-tests.sh           # database + RLS regression tests
```

All of the above run in CI on every push/PR — see
[`.github/workflows/ci.yml`](./.github/workflows/ci.yml). **This environment
was built assuming you have no local system to run builds on**: push to a
branch and let GitHub Actions be your build/test runner. Everything above
also happens to work locally if you do have a machine for it.

## Security model (read this before touching auth/RLS/grading code)

1. **RLS is the enforcement layer, not client checks.** Every table has RLS
   enabled and `FORCE ROW LEVEL SECURITY` set. Default posture: no access
   unless an explicit policy grants it.
2. **Anything that represents "proof of skill" (quiz answers, lab flags,
   skill_evidence, user_skill_states) has no direct client write path.**
   Writes only happen through `SECURITY DEFINER` functions that
   independently verify the outcome (see
   `supabase/migrations/20260921000010_grading_and_evidence.sql`).
3. **Role changes require an existing admin or `service_role`.** There is
   no INSERT/UPDATE policy on `user_roles` for a user's own row.
4. **Entitlements are never client-settable.** `subscriptions` has no client
   write path; `set_active_subscription()` re-checks `is_admin() OR
   service_role` internally even though RLS already blocks direct writes
   (defense in depth).
5. Every one of the above is backed by an executable regression test in
   `supabase/tests/`, not just a comment asserting it's true. Run
   `bash scripts/run-sql-tests.sh` after any change to migrations.

## Documentation index

- [`MANUAL_SETUP.md`](./MANUAL_SETUP.md) — every step that requires you
  personally (Supabase project creation, OAuth apps, API keys, deployment).
- [`RELEASE_CHECKLIST.md`](./RELEASE_CHECKLIST.md) — what's verified vs.
  outstanding, honestly tracked.
- [`SECURITY_AUDIT.md`](./SECURITY_AUDIT.md) — security findings and their
  status.
- [`docs/adr/`](./docs/adr/) — why the architecture is shaped the way it is.
