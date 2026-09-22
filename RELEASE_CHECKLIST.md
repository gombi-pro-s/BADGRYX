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
- [x] 91 SQL regression assertions passing against a real Postgres instance
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
- [x] Labs with an authored environment (`has_terminal`) get a real
      interactive terminal simulator (see "Labs / Terminal / Cyber Range"
      below); labs without one clearly label that in the UI rather than
      implying a live environment

## Labs / Terminal / Cyber Range

- [x] Lab bookkeeping (instances, hints, flags, progress) — real, tested
- [x] Terminal simulator — schema: `lab_environments` (the authored virtual
      filesystem/hostname, RLS-locked exactly like `lab_flags` — never
      selectable by a non-staff session, see
      `docs/adr/0009-lab-terminal-server-side.md`) and
      `lab_terminal_commands` (an append-only, owner-scoped transcript of
      every command run). `labs.environment_spec` (an unused placeholder
      column) was dropped and replaced by this properly-secured table.
      8 SQL regression assertions (`supabase/tests/009_lab_terminal_rls.sql`)
- [x] Terminal command interpreter (`lib/terminal/interpreter.ts`) — pure,
      no I/O, real Unix-like subset: `pwd cd ls cat echo head tail wc file
      find grep whoami id hostname uname sudo clear help`. Deliberately not
      a shell (no pipes/redirects/chaining) — documented as an honest scope
      boundary, same as the scanner's rule engine not being a real parser.
      `sudo` enforces a per-user allow-list from the spec and elevates only
      for that one call, never persisting. 57 unit tests (path resolution/
      implicit directories + every command's real and error-path behavior)
- [x] Server-side terminal execution engine (`lib/terminal/execute.ts`) —
      verifies lab_instance ownership + running status through the
      caller's own RLS-scoped session first, only then escalates (via
      `createAdminClient()`, narrowly, for this one read) to fetch the
      staff-only environment spec; persists updated state and an
      append-only transcript row back through the caller's own session.
      `POST /api/labs/[labInstanceId]/terminal` — requireUser, zod,
      2000-char command cap
- [x] `labs.has_terminal` — a denormalized, non-secret flag (kept accurate
      by trigger) so the learner UI can offer a terminal launcher without
      ever querying `lab_environments` directly
- [x] Admin authoring UI for lab environments (`/admin/labs/[labId]`'s
      "Terminal environment" section) — a JSON spec editor, validated
      server-side against the exact same `environmentSpecSchema` the
      execution engine parses with, so a spec that saves is guaranteed
      runnable; multiple variants (by `variant_seed`) supported
- [x] One complete real terminal lab seeded end-to-end: "Linux Privilege
      Escalation: Misconfigured Sudo" (`linux-privesc-sudo-cat`) — a real,
      well-known technique (an unrestricted sudo rule on `cat`, documented
      in GTFOBins), not an invented puzzle. Proven actually solvable
      through the interpreter (not just schema-valid) by
      `lib/terminal/__tests__/seeded-lab.test.ts`, which also caught a real
      design bug: the interpreter didn't enforce the `owner`/`perms` fields
      it rendered in `ls -l`, so the flag was readable via plain `cat`
      without ever needing `sudo`. Fixed by adding real (if simplified)
      Unix read-permission enforcement to `cat`/`head`/`tail`/`wc`/`grep`
      before this lab shipped — see `lib/terminal/path.ts`'s `canReadFile`.
      8 more unit tests covering permission enforcement specifically
- [x] Three more real terminal labs, proving the engine on distinct
      scenarios and command patterns (none needing privilege escalation --
      every file involved is world-readable, matching how real OSINT/
      enumeration/forensics work): **Secrets Enumeration** (`find`/
      `ls -la`/`cat` locates a forgotten `.env.backup` with a leaked key,
      while the live `.env` is a readable decoy), **Digital Forensics**
      (`wc -l`/`grep` isolates one real `Accepted password` line among 13
      `Failed password` noise lines in a realistic auth.log), **Service
      Enumeration** (`grep -r`/`find` across four services' version files
      locates the one flagged EOL/CRITICAL, then reads its notes for the
      flag). Each proven solvable through the interpreter, not just
      schema-valid, by a dedicated test file per lab (10 more unit tests)
- [x] Terminal UI component (`/labs/[labId]/terminal.tsx`) — a real
      scrollback + input, up/down-arrow command recall, connects on mount
      via a silent "learn the real cwd/user/hostname" call (never asserted
      by the client), persists and replays the real transcript across page
      reloads. Wired into `/labs/[labId]`, shown only when `lab.has_terminal`
      is true and the learner has a running instance; the "not provisioned
      yet" warning banner now only shows for labs that genuinely have no
      terminal
- [ ] Lab engine runtime for an actual live/networked target (a real VM or
      container per attempt) is intentionally out of scope — the terminal
      simulator is a deterministic virtual environment, not a provisioned
      live host; this remains clearly labeled wherever it matters
- [ ] Cyber Range interconnected environments (not started)

## OSINT / Forensics / Blue-Purple Team

- [x] Investigation workspace schema: `investigations`, `investigation_artifacts`
      (public case evidence -- WHOIS records, email headers, log excerpts,
      chat transcripts; real synthetic text data, not a claim of doing
      actual image/PCAP forensics), `investigation_questions`/
      `investigation_choices` (mixed multiple_choice + exact_text, hidden
      answer key exposed safely via `investigation_questions_for_attempt`,
      same pattern as `quiz_questions_for_attempt`), `investigation_instances`
      (a genuinely private per-user notes scratchpad -- not even
      staff-readable, unlike almost every other owner-scoped table in this
      app), `investigation_submissions`
- [x] `submit_investigation_answers()` — grades multiple_choice by set
      equality and exact_text by normalized (trimmed/lowercased) SHA-256
      comparison, mirroring `submit_quiz_attempt()`/`submit_lab_flag()`;
      records `skill_evidence`
- [x] Added `'investigation'` to `skill_evidence_type` and to
      `recompute_skill_state()`'s DEMONSTRATED/MASTERED rules, alongside
      `unguided_lab`/`ctf` — independent correct answers are the same
      category of unguided demonstration
- [x] 9 SQL regression assertions
      (`supabase/tests/010_investigation_rls.sql`): artifact visibility
      follows `published`, answer key hidden but the safe view works,
      mixed-type grading (including answer normalization) reaches
      `DEMONSTRATED`, a wrong exact-text answer fails independently of a
      correct multiple-choice one, and the notes-privacy model (not even
      staff can read another user's notes)
- [x] Admin CRUD for investigations (`/admin/investigations`) — case
      metadata, skill tagging, evidence artifacts manager, and a mixed
      multiple_choice/exact_text question builder; exact_text answers are
      hashed server-side on submit (same discipline as lab/CTF flags,
      never sent to the browser or stored in plaintext)
- [ ] Learner investigation workspace UI (`/investigate`) — not built yet
- [ ] One complete real investigation seeded end-to-end — not built yet
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

- [x] Schema: `scans`, `scan_files`, `scan_findings`, `scan_finding_status_events`
      — owner-scoped, staff-readable, size-bounded file content
      (`supabase/migrations/20260922000002_security_scanner.sql`)
- [x] `transition_scan_finding_status()` — the only way a finding's status
      changes; validates ownership and the attack → fix → retest state
      graph, writes an append-only history row, audit-logged. See
      `docs/adr/0008-scanner-finding-lifecycle.md`.
- [x] `scans.total_files` / `total_findings` / `findings_by_severity` kept
      accurate by triggers, never client-asserted
- [x] 11 SQL regression assertions (`supabase/tests/007_scanner_rls.sql`):
      ownership isolation, cross-user insert/transition rejection, illegal
      state transitions rejected, full legal attack → fix → retest path,
      idempotent re-assertion, audit log coverage
- [x] Deterministic static-analysis rule engine (`lib/scanner/rules/*.ts`):
      12 rule modules covering secrets, SQL injection, XSS, command
      injection, path traversal, insecure eval, weak crypto, insecure CORS,
      insecure cookies, cleartext HTTP, prototype pollution, and unsafe
      deserialization — pure functions, no model call, no network access.
      Explicitly heuristic (regex/pattern-based, not a real parser or
      dataflow analysis) and documented as such; that's why every finding
      carries a `verification_status` and feeds the attack → fix → retest
      workflow rather than being asserted as ground truth. 44 unit tests
      (true positive + false positive per rule)
- [x] Scan orchestration (`lib/scanner/orchestrate.ts`) — runs every rule
      against each submitted file and persists scan/files/findings through
      the calling user's own session (no service-role bypass, so RLS still
      applies to every write)
- [x] `POST /api/scanner/scan` — requireUser, zod-validated
      (title/targetType/files, ≤20 files, ≤300KB each), rate-limited via
      the real entitlement engine (`scanner_daily_scans`, 5/day on free —
      same pattern as the Mentor's quota), audit-logged
- [x] 4 unit tests for the file-count/size validation guard
      (`lib/scanner/__tests__/validate.test.ts`)
- [x] AI-assisted enrichment layer: `POST /api/scanner/findings/[id]/enrich`
      calls Anthropic (model `claude-sonnet-5`), grounded only in the real
      finding's evidence (fetched server-side, RLS-enforced), and writes
      through `enrich_scan_finding()` — a function with no parameter for
      severity/category/verification_status/status, so it structurally
      cannot invent or reclassify a finding, only improve its explanation/
      impact/remediation/secure_example text (`ai_enriched` flag set). The
      scanned source's evidence (the one attacker-influenceable input in
      this flow) is explicitly labeled untrusted in the prompt and never
      concatenated with the fixed system instructions — same three-way
      separation as ADR 0007, see ADR 0008
- [x] `scanner_daily_enrichments` entitlement (20/day on free) enforced by
      `POST /api/scanner/findings/[id]/enrich` via
      `count_my_scan_enrichments_today()` — a SECURITY DEFINER helper
      scoped to the caller's own audit_log entries, since audit_log itself
      is admin-only readable by RLS
- [x] 6 SQL regression assertions
      (`supabase/tests/008_scanner_enrichment_rls.sql`): enrichment never
      changes fact-of-record fields, cross-user enrichment rejected, empty
      text rejected, audit-logged, enrichment count reflects only the
      caller's own activity
- [x] 8 unit tests for the enrichment prompt (evidence isolation, injection
      resistance, structural non-fabrication) — `lib/scanner/__tests__/enrichment-prompt.test.ts`
- [x] `/scanner` UI — paste-or-upload form (`ScanUploader`), a posture
      summary aggregated across the user's last 20 scans
      (`findings_by_severity`, server-computed), a past-scans list, and a
      scan detail page (`/scanner/[scanId]`) with per-finding evidence/
      explanation/impact/remediation/secure-example/references, an
      "Enrich with AI" action, and attack → fix → retest status buttons
      (calling `transition_scan_finding_status()` directly, same pattern
      as the Labs workspace's RPC calls — the DB, not the UI, is what
      actually enforces which transitions are legal)
- [x] `/scanner` added to the auth-wall middleware and app nav; e2e-tested
      (`e2e/smoke.spec.ts`) alongside every other protected route
- [x] `SeverityBadge` / `FindingStatusBadge` components + 14 unit tests;
      3 more for the UI's transition-map (`lib/scanner/status-transitions.ts`)
      asserting it matches the database function's edge set exactly, so a
      change to one without the other fails a test
- [ ] Manually clicking through an authenticated scan (paste code → view
      findings → transition status → enrich) has NOT been done — this
      sandbox has no real Supabase Auth server (see `scripts/local-test-db.sh`'s
      hand-rolled auth stub, built only for the SQL test harness), so there's
      no way to log in a browser session here. Verified instead by: `tsc
      --noEmit`, ESLint, a full production build succeeding for
      `/scanner` and `/scanner/[scanId]`, 14 e2e tests including the new
      `/scanner` auth-wall redirect, and 114 unit tests. A real
      authenticated click-through needs a provisioned Supabase project
      (`MANUAL_SETUP.md` §2) — do that first if you want this verified
      live.

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

- [x] 91 SQL regression assertions (RLS + grading + entitlements + a full
      seeded-content walkthrough)
- [x] 193 unit tests (validation logic, env guards, UI components, AI
      Mentor prompt safety, security scanner rule engine + enrichment
      prompt + status transitions, lab terminal path resolution + command
      interpreter + real-permission enforcement + the seeded lab's
      solvability)
- [x] 14 e2e smoke tests (public pages, auth wall across all protected
      sections including `/scanner`, login error handling)
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
