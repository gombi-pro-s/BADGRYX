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
- [x] Admin UI for granting/revoking *other users'* roles — `/admin/users`
      (search by email/username/display_name via `admin_search_users()`,
      click a role chip to grant/revoke instructor/moderator/admin).
      `grant_platform_role()`/`revoke_platform_role()` are now the only
      way this app's own UI changes a role — each is audit-logged
      (`user_role.granted`/`user_role.revoked`), and an admin is blocked
      from revoking their own admin role (lockout prevention) while still
      able to revoke a *different* admin's. `admin_search_users()` is the
      one narrowly-scoped admin-only read across the `auth.users`
      boundary (email/username/display_name/current roles only — no
      password hash, no raw metadata) since `profiles` never stores email
      by design. 9 SQL regression assertions
      (`supabase/tests/016_admin_role_management.sql`)

## Database / Security Rules

- [x] Every table has RLS enabled and `FORCE ROW LEVEL SECURITY`
- [x] 144 SQL regression assertions passing against a real Postgres instance
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
- [x] "Prove Your Skill" matrix UI — `/skills` now renders a real per-skill
      table with one column per `skill_evidence_type` (theory/quiz/
      guided_lab/unguided_lab/ctf/assessment/remediation/retest); each cell
      is the best real outcome (passed/partial/failed/not attempted) from
      that user's actual `skill_evidence` rows, computed with the same
      "ever passed wins" priority the state machine itself uses, not a
      fabricated summary. `/skills/[skillId]` adds a per-skill detail page:
      prerequisites, a plain-language explanation of the current state
      lifted directly from `recompute_skill_state()`'s documented rules,
      and the full real evidence history (type/outcome/source/score/hint
      level/timestamp)

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
- [x] A real `pro` plan seeded with real, better-than-free entitlement
      values (`20260922000015_seed_pro_plan.sql`) — previously only `free`
      existed, so there was nothing to actually upgrade to
- [x] Live payment provider integration — real, complete code for Stripe,
      Paystack, and Flutterwave (checkout initiation + webhook signature
      verification + processing), gated by environment variables exactly
      like `ANTHROPIC_API_KEY` (see ADR 0011). Pure signature-verification
      and request-building logic (`lib/billing/{stripe,paystack,
      flutterwave}.ts`) is fully unit-tested (24 tests) without needing a
      real account; the `fetch()` I/O wrappers
      (`lib/billing/{stripe,paystack,flutterwave}-client.ts`) are
      `server-only`-guarded, mirroring `lib/mentor/prompt.ts` vs
      `client.ts`. Zero new npm dependencies — all three integrations are
      hand-rolled against each provider's REST API with Node's built-in
      `crypto`, not an SDK, the same "auditable in this repo, not trusted
      to a third party" discipline as the terminal interpreter and scanner
      rule engine
- [x] Three webhook routes (`/api/billing/webhook/{stripe,paystack,
      flutterwave}`), each idempotent via `billing_webhook_events`
      (keyed by `(provider, provider_event_id)` — a unique-constraint hit
      means "already processed," not an error), each running as
      `service_role` and calling the same `set_active_subscription()` RPC
      ADR 0005 already built
- [x] `/settings/billing` UI — current plan + real entitlement values,
      three "Upgrade with ..." buttons that create a real checkout
      session and redirect; a provider with no configured keys renders as
      a disabled "(not configured)" button rather than crashing
- [x] `supabase/tests/004_entitlements.sql` extended: the real `pro` plan
      (not the pre-existing escalation-prevention test fixture, which was
      renamed off the now-real `pro` slug) grants real, better-than-free
      entitlements once `set_active_subscription()` activates it
- [ ] **This has NOT been tested against a real Stripe/Paystack/
      Flutterwave account or a live webhook delivery** — no external
      account or API keys exist in this build environment (see ADR 0011,
      MANUAL_SETUP.md §4). Verified instead by: 24 unit tests covering
      every signature-verification edge case (wrong secret, tampered
      body, replay window, malformed/missing header) and request-building
      logic for all three providers, a full production build succeeding
      for all three webhook routes and `/settings/billing`, and a SQL
      regression test proving the real `pro` plan's entitlements resolve
      correctly once active. A real click-through and webhook delivery
      needs a real provider account and keys — do that first (§4) if you
      want this verified live.
- [x] Recurring-subscription cancellation auto-downgrade is implemented
      for all three providers (Stripe's `customer.subscription.deleted`,
      Paystack's `subscription.disable`, Flutterwave's
      `subscription.cancelled`). While wiring Flutterwave's, found and
      fixed a real latent bug in Paystack's handler too: matching a
      cancellation to a subject by a bare `provider_customer_id` breaks
      (`.maybeSingle()` errors on >1 row) once a customer has
      cancelled-then-resubscribed, since that id persists across their
      whole history with the provider — both handlers now scope the
      match to the subject's currently active-ish row. Flutterwave's
      exact webhook event name/payload isn't verified against a live
      account (none exists in this build environment) — confirm against
      real deliveries when configuring it for real, see ADR 0011

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
- [x] Learner investigation workspace UI — `/investigate` (list, with a
      per-user solved/best-score badge) and `/investigate/[id]` (case
      briefing, evidence artifacts as a real case board, a private
      autosaved notes scratchpad, and a mixed multiple_choice/exact_text
      answer form wired to `submit_investigation_answers()`); added to the
      auth-wall middleware and app nav, e2e-tested alongside every other
      protected route
- [ ] "Ask Mentor" deep link from an investigation — deliberately not
      added yet; `MentorContextType` doesn't have an `investigation` value,
      and adding one touches the Mentor's context builder/prompt, out of
      scope for this task
- [x] One complete real investigation seeded end-to-end: "Phishing
      Campaign: The Fake Invoice" (`phishing-fake-invoice`) — 4 internally
      consistent artifacts (spoofed email headers, a WHOIS record for the
      lookalike domain registered 3 days before the attack, an internal
      incident-response chat transcript, and a VPN login log proving
      credential theft actually succeeded) and 5 questions (mixed
      multiple_choice/exact_text) that require correlating timestamps and
      details across all four. Proven genuinely solvable through the real
      grading RPC (not just schema-valid) by
      `supabase/tests/011_seeded_investigation_e2e.sql`, including
      realistic messy-case/whitespace input on the exact_text answers
- [x] Three more real investigations, proving the workspace on distinct
      evidence-correlation patterns: **Data Breach Timeline
      Reconstruction** (a firewall transfer log + file metadata + a team
      chat log trace initial access to a leaked, never-rotated
      service-account password), **Social Engineering Pretext Analysis**
      (a helpdesk call transcript + a public social media profile + a
      spoofed follow-up email show how a caller built false credibility
      from public OSINT), **Malware Beaconing: Identify the C2 Server** (a
      network capture summary + a Startup-folder persistence artifact + a
      WHOIS record). None require privilege escalation or a terminal --
      pure evidence correlation. Proven genuinely solvable (correct
      answers pass, wrong answers genuinely fail) by
      `supabase/tests/012_more_seeded_investigations_e2e.sql`
- [ ] Blue/Purple Team scenario linkage (not started)

## CTF / Arena / Exams / Capstones

- [x] Schema + grading + anti-cheat constraint for CTF challenges
- [x] Admin CMS + learner UI for CTF challenges (see above)
- [x] Exam mode UI: `/exams` (published `is_exam` quizzes, per-user
      passed/attempts-used status) and `/exams/[quizId]` (a dedicated
      timed take flow, not the lesson-embedded quiz component). A real
      countdown timer from `time_limit_minutes` auto-submits whatever is
      answered when it hits zero; an honest `hint_policy` banner states
      the exam's rules up front (there is no actual hint content behind
      it to gate — the copy says exactly that, never implying a feature
      that doesn't exist); prior attempts and `max_attempts` are shown and
      enforced client-side ahead of the RPC's own authoritative check;
      `single_choice`/`true_false` render as radio buttons and
      `multi_choice` as checkboxes with real exact-set grading (no partial
      credit) — the lesson-embedded `QuizAttempt` only ever supported
      single-choice, a real gap this closes for exam-authored content.
      **Known, documented limitation**: the timer is client-side only,
      starting when the page loads — there is no server-side exam-session
      record (unlike `lab_instances`/`investigation_instances`), so a page
      refresh restarts the clock and a determined user could pause the JS
      timer via devtools. Not enforced timing, stated as such rather than
      implied. Seeded one real standalone (no `lesson_id`) exam quiz --
      "SQL Injection: Practical Assessment" (4 questions, mixed
      single/multi-choice, `hint_policy='none'`) -- proven genuinely
      solvable through `submit_quiz_attempt()` (not just schema-valid),
      including that `is_exam=true` records `'assessment'` evidence (not
      `'quiz'`) and an incomplete multi-select answer genuinely fails with
      no partial credit, by `supabase/tests/015_seeded_exam_e2e.sql`
- [x] Capstone schema with staff-reviewed report submissions
- [ ] Arena/mission UI (CTF timers/leaderboard specifically) — not started
- [x] Capstone submission/review UI: `review_capstone_submission()` is now
      the only way a submission's status changes (the blanket staff UPDATE
      RLS policy was dropped, mirroring the scanner finding lifecycle in
      ADR 0008) — it independently re-verifies staff status, blocks a
      staff member from reviewing their own submission, and blocks
      re-reviewing an already-passed submission. Added `'capstone'` to
      `skill_evidence_type` and to `recompute_skill_state()`'s
      DEMONSTRATED/MASTERED rules (the same independent-demonstration
      weight as `unguided_lab`/`ctf`/`investigation`) — a passed capstone
      now genuinely advances the skills it's tagged with via real
      `skill_evidence`, and a `needs_revision` review records a real
      failed attempt rather than being silently dropped; `capstone_skills`
      existed since day one but was never actually used until this. 8 SQL
      regression assertions (`supabase/tests/014_capstone_review.sql`).
      Admin CMS at `/admin/capstones` (CRUD, skill tagging, related-lab
      tagging, and an inline review queue per capstone with a
      status/notes form). Learner UI at `/capstones` (published list with
      a per-user latest-status badge) and `/capstones/[capstoneId]`
      (description, linked skills/labs, submission history with reviewer
      notes, and a report submission form)

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
- [x] Org-instructor visibility extended to all 8 gradeable-outcome tables:
      `skill_evidence`/`user_skill_states`/`lab_instances`/`lab_progress`
      (already had it) plus `quiz_attempts`/`ctf_submissions`/
      `capstone_submissions`/`investigation_submissions` (added in
      `20260922000012_org_instructor_visibility_and_invitations.sql`) — an
      instructor/team_owner/org_admin can see a fellow org member's real
      graded results everywhere skill evidence is produced, not just some of
      them
- [x] Invitation lifecycle: `create_organization_invitation()` (generates
      and hashes a random token, enforces `seat_limit` for real, only
      callable by an org admin/team owner) and
      `accept_organization_invitation()` (validates not-revoked/not-
      accepted/not-expired/matching-email before creating membership) — see
      `docs/adr/0010-org-invitations-manual-link.md` for why there's no
      email send (no email provider is configured anywhere in this app; the
      raw link is shown once in the admin UI for manual sharing, same
      honesty as the billing deferral in ADR 0005)
- [x] 11 SQL regression assertions
      (`supabase/tests/013_org_instructor_visibility_and_invitations.sql`):
      an org instructor sees a fellow member's real quiz/CTF/capstone/
      investigation results (via the real grading RPCs, not planted rows);
      an instructor of an unrelated org sees none of it; a plain
      (non-instructor) org member also can't; invitation accept happy path,
      double-accept rejection, wrong-email rejection, expired/revoked
      rejection, seat_limit genuinely enforced, and only an org admin/team
      owner can create an invitation
- [x] Org UI: `/orgs` (list the user's organizations, create one — creator
      auto-becomes `team_owner` via the existing trigger), `/orgs/[orgId]`
      (member roster; org admins additionally get an invite-link generator
      and a pending-invitations list with revoke), `/invite/[token]` (an
      accept-invitation page outside the app's auth-walled route group
      specifically so an unauthenticated visitor's `?next=` redirect
      round-trips back to the same invite link after login/signup — see the
      ADR)
- [x] Instructor dashboard (`/orgs/[orgId]/dashboard`) — a real per-member
      table (skills proven/in-progress, labs completed, quizzes passed, CTF
      solved, investigations passed), built entirely from the
      now-RLS-covered tables above; nothing self-reported
- [ ] Manually clicking through the org/invite/dashboard flow in a browser
      has NOT been done — same sandbox limitation as every other UI phase
      this session (no real Supabase project to authenticate against here;
      see the `/scanner` entry above). Verified instead by: 108 SQL
      regression assertions (13 files, all passing), `tsc --noEmit`, ESLint,
      a full production build succeeding for every new route, and 17 e2e
      tests including the 2 new ones for `/orgs` and `/invite/[token]`'s
      auth-wall redirects. A real click-through needs a provisioned
      Supabase project (`MANUAL_SETUP.md` §2).
- [x] Org member management: `/orgs/[orgId]` now has a per-member role
      dropdown (org admin/team owner only) and a Remove/Leave button (org
      admin for anyone, or any member for themselves) built on two new
      SECURITY DEFINER functions,
      `update_organization_member_role()`/`remove_organization_member()`
      (`supabase/migrations/20260922000019_org_member_management.sql`),
      not the raw RLS UPDATE/DELETE path. Building the real UI surfaced a
      gap the RLS policies alone don't cover: nothing stopped an org_admin
      from demoting or removing the organization's only `team_owner`,
      leaving it with no one able to manage it. Both functions now block
      that (the guard is a live count of `team_owner` rows, not a
      self-check — it also stops the last owner removing/demoting
      *themselves*), and both are audit-logged. See
      `docs/adr/0013-org-member-management.md`.

## Privacy / Data protection

- [x] Account data model supports deletion: every user-OWNED table has
      real `ON DELETE CASCADE` to `auth.users.id` (this was already
      correct); every ATTRIBUTION column (`granted_by`/`created_by`/
      `invited_by`/`actor_id`/`reviewer_id`) now correctly has
      `ON DELETE SET NULL` instead of defaulting to `NO ACTION` — a real,
      previously-latent bug fixed while building the flow below: deleting
      a user who had ever granted a role, created an org, authored
      content, reviewed a capstone, or been logged to `audit_log` (i.e.
      almost any admin) would have failed outright with a foreign key
      violation. See `docs/adr/0012-account-deletion.md`.
- [x] User-facing "delete my account" flow — `/settings/privacy`: type
      your exact email to confirm, then `deleteMyAccountAction()`
      audit-logs the deletion (while the session is still valid) and
      calls the GoTrue Admin API's `deleteUser()` (the only place in the
      app that constructs the `service_role` client for a user-triggered
      action, narrowly scoped to the caller's own already-verified id,
      mirroring ADR 0009's escalation pattern), then signs out and
      redirects to `/login`. Proven end-to-end by
      `supabase/tests/018_account_deletion.sql`: a real `DELETE FROM
      auth.users` succeeds, every historical record the deleted user
      touched survives with its attribution nulled, and their own owned
      rows are genuinely gone
- [x] User-facing data export — `GET /api/account/export` downloads a
      JSON bundle of every category of the caller's own data (profile,
      roles, org memberships, skill graph, learning/lab/CTF/investigation/
      capstone activity, mentor conversations, scanner scans, subscription
      history). Every query explicitly filters to the caller's own id
      rather than relying on RLS breadth alone — an instructor/admin
      session can see other users' rows on several tables by RLS design,
      and this route's job is "your own data," not "everything your
      session can see"
- [ ] Documented retention policy (not written)

## Logging / Auditing

- [x] Append-only audit log, server-attributed, admin/org-admin readable only
- [x] Audit coverage, real and growing (not every section-34 action, but a
      meaningful, honestly-scoped set): grading (`quiz.attempt.submitted`,
      `lab.flag.submitted`, `ctf.flag.submitted`,
      `investigation.answers.submitted`), billing
      (`subscription.changed`), platform roles
      (`user_role.granted`/`user_role.revoked`), capstone review
      (`capstone.submission.reviewed`), scanner (`scan.completed`, finding
      status transitions, enrichment), the AI Mentor
      (`mentor.message.sent`), and — new this phase — the full
      organization invitation lifecycle (`organization.created`,
      `org.invitation.created`, `org.invitation.accepted`,
      `org.invitation.revoked`, all real `organization_id`-scoped so an
      org's own admin can see their org's trail via the RLS branch that
      already existed but nothing populated) and every content type's
      publish/unpublish toggle (`learning_path`/`module`/`lesson`/`lab`/
      `quiz`/`ctf_challenge`/`investigation`/`capstone` `.published`/
      `.unpublished`, 8 call sites). 4 new SQL regression assertions
      (`supabase/tests/017_audit_log_expansion.sql`) prove the org
      invitation events are genuinely organization-scoped, not just
      logged — a different org's admin cannot read them
- [ ] Still not instrumented, an honest scope boundary rather than an
      oversight: login/logout/password-reset (Supabase Auth's own system
      has separate logging for these; wiring this app's `audit_log` to
      every auth event would need an Auth hook, out of scope here), and
      fine-grained content CRUD (create/edit/delete of an individual
      lesson/question/etc., as opposed to its publish state, which is the
      signal actually worth a support/debugging trail)

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

- [x] 144 SQL regression assertions (RLS + grading + entitlements + a full
      seeded-content walkthrough + org-instructor visibility + invitations +
      capstone review lifecycle + the seeded standalone exam + the real
      pro plan's entitlements + admin role management + org-scoped audit
      log coverage + account deletion + org member management)
- [x] 222 unit tests (validation logic, env guards, UI components including
      the Prove Your Skill matrix's evidence-cell indicator, AI Mentor
      prompt safety, security scanner rule engine + enrichment prompt +
      status transitions, lab terminal path resolution + command
      interpreter + real-permission enforcement + the seeded lab's
      solvability, live billing signature verification + request-building
      for Stripe/Paystack/Flutterwave)
- [x] 19 e2e smoke tests (public pages, auth wall across all protected
      sections including `/scanner`/`/orgs`/`/capstones`/`/exams`, an
      invite link's `?next=` round-trip, login error handling)
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
