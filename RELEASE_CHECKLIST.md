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
- [x] Flutter mobile app scaffolded (`mobile/app`) — see Mobile readiness
      section below for the full, current state
- [x] i18n framework in place — `lib/i18n/` (a hand-rolled dictionary +
      fallback + `{param}` interpolation, no new dependency, no `[locale]`
      URL-prefix routing — every route keeps its exact path; see ADR
      0025) with a real bilingual slice (English/Spanish): the public
      landing page and `/settings`'s "Language" section, both genuinely
      switchable via a cookie that persists across reloads. The rest of
      the app remains English-only, stated plainly in the settings copy
      itself. This specifically unblocks (but does not itself build)
      the content-translations table ADR 0017 deferred.
- [x] PWA / offline support — installable (real `app/manifest.ts`, two
      stable-URL icon routes at `/icons/192`/`/icons/512` generated with
      `next/og`'s `ImageResponse`, no image-processing dependency, plus
      `apple-icon.tsx`) and a hand-written `public/sw.js` (no Workbox/
      next-pwa/serwist) with a deliberately narrow scope: precaches
      `/offline`, falls back to it on a failed navigation, and
      cache-first-with-network-fallback for `_next/static/` build assets
      only. It never intercepts API routes, Supabase calls, or any
      dynamic/authenticated page — this app is honest that it needs a live
      backend for nearly everything, not claiming full offline
      functionality it doesn't have. See ADR 0022.

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
- [x] MFA: TOTP enrollment (`/settings/security` — QR code + manual
      secret, verify-to-activate, list/remove factors) via Supabase
      Auth's own `supabase.auth.mfa.*` API, no new schema/migration
      needed. Real step-up enforcement, not just enrollment: `requireUser()`
      (the function nearly every protected page/action already calls)
      checks `getAuthenticatorAssuranceLevel()` and redirects to the new
      `/login/verify-mfa` challenge page whenever a session hasn't
      completed a verified factor's second step, mirrored in
      `middleware.ts` for UX and in `signInAction()` right after password
      sign-in. See `docs/adr/0015-mfa.md`. No SQL regression test exists
      for this phase — genuinely no Postgres surface to test (MFA state
      lives in `auth.mfa_factors`, owned entirely by GoTrue)
- [x] Application-layer rate limiting on the login endpoint: three
      `SECURITY DEFINER` functions
      (`supabase/migrations/20260922000020_login_rate_limiting.sql`) block
      an email after 5 failed attempts in 15 minutes, called from
      `signInAction()` before/after `supabase.auth.signInWithPassword()`
      (in addition to, not instead of, whatever Supabase project-level
      limits are configured — see `MANUAL_SETUP.md`). Email-keyed, not
      IP-keyed — a deliberate, documented trade-off, see
      `docs/adr/0014-login-rate-limiting.md`. 6 SQL regression assertions
      (`supabase/tests/020_login_rate_limiting.sql`)
- [x] CAPTCHA/bot protection on signup: Cloudflare Turnstile, fully wired
      end to end (`apps/web/src/lib/turnstile/` — `turnstile.ts` pure
      request/response logic, `turnstile-client.ts` the real
      `siteverify` call, `env.ts` the `isTurnstileConfigured()` guard) and
      enforced in `signUpAction()`. Same "real integration, graceful
      no-op without real keys" shape as the billing providers: without
      `NEXT_PUBLIC_TURNSTILE_SITE_KEY`/`TURNSTILE_SECRET_KEY` configured
      (see `MANUAL_SETUP.md` §8), `/signup` renders no widget and nothing
      is enforced — identical to today's behavior, not a broken signup
      flow. 6 unit tests for the pure verify-request/response logic
      (`apps/web/src/lib/turnstile/__tests__/turnstile.test.ts`)

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
- [x] 178 SQL regression assertions passing against a real Postgres instance
      (`bash scripts/run-sql-tests.sh`), covering identity/RBAC, skill graph,
      grading pipeline, entitlements, announcements, and a full
      seeded-content walkthrough
- [x] Audit log is append-only and unforgeable (verified by test)
- [x] 10 real bugs found and fixed during development — see
      `SECURITY_AUDIT.md` (AUDIT-001 through AUDIT-010). 9 of the 10 have a
      dedicated regression test; AUDIT-009 (a context-type allowlist drift
      between `/mentor`'s page and its API route) was instead fixed
      structurally, by replacing both hand-duplicated arrays with one
      shared exported constant, which makes that specific bug class
      impossible to reintroduce rather than merely tested for
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
- [x] Announcements — platform-wide (staff-authored, `/admin/announcements`)
      or org-scoped (instructor/team_owner/org_admin-authored,
      `/orgs/[orgId]/announcements`), shown on `/dashboard` while published
      and not expired. Plain RLS write gate (`is_org_instructor()` helper
      mirrors `is_org_admin()`), no SECURITY DEFINER function needed —
      nothing here is graded. Unlike other content types, a real delete is
      offered (nothing else references an announcement's id, so nothing
      can be orphaned by removing one) — see ADR 0017.
- [x] Content translations for announcements — `announcement_translations`
      (one optional row per `(announcement_id, locale)`, RLS mirroring the
      parent announcement's own visibility/write rules exactly), an
      optional "Spanish translation" fieldset on the admin and org-scoped
      create/edit forms, and `/dashboard` rendering the matching
      translation (via the pure, unit-tested `pickAnnouncementText()`)
      instead of the raw English row when the viewer's locale is Spanish.
      Other user-authored content types (paths, lessons, etc.) remain
      untranslated — a separate, larger decision, not bundled into this
      one. See ADR 0038.
- [x] Content translations extended to learning paths and lessons —
      `learning_path_translations`/`lesson_translations` (same shape and
      RLS pattern as `announcement_translations`, mirrored through the
      parent row's own `_select_published_or_staff`/`_staff_write`
      policies via `EXISTS`), the same optional Spanish fieldset on the
      admin path/lesson forms (path translation requires only a title —
      a path's own description is optional too; a lesson translation
      requires both title and content, since `content_markdown` is NOT
      NULL on the base row), and `/learn`, `/learn/[pathId]`, and the
      lesson-reading page all rendering the matching translation (via
      the pure, unit-tested `pickPathText()`/`pickLessonText()`) instead
      of the raw English row. Modules remain untranslated by design — no
      body text and no edit form either, so there's nothing to add a
      fieldset to. +7 vitest tests (323 total). See ADR 0064.
- [x] Bulk import/export of content — scoped to learning paths (the one
      content type with a real FK hierarchy; labs/CTF are only informally
      tied to a path via shared skill tags, and their flags are stored only
      as a hash, so a real export/import for them needs its own design —
      see ADR 0016). `GET /admin/paths/[pathId]/export` downloads a
      `icorepen.learning_path.v1` JSON bundle (path → modules → lessons →
      skill tags by slug → quiz → questions → choices);
      `/admin/paths/import` accepts a pasted/uploaded bundle and always
      creates a new path, never merges into an existing one. A failure
      partway through is cleaned up automatically (the partial path is
      deleted, cascading through everything created under it) rather than
      leaving orphaned rows. Verified by 9 unit tests on the pure
      schema/parser (`lib/content-io/path-bundle.ts`), `tsc`, ESLint, a
      clean build (both routes present), and 1 new e2e test. A real
      authenticated export→import round trip needs a provisioned Supabase
      project — do that first if you want this verified live.

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
      find grep whoami id hostname uname sudo ssh exit clear help`.
      Deliberately not a shell (no pipes/redirects/chaining) — documented
      as an honest scope boundary, same as the scanner's rule engine not
      being a real parser. `sudo` enforces a per-user allow-list from the
      spec and elevates only for that one call, never persisting. `ssh`/
      `exit` pivot between multiple networked hosts in a single lab
      environment (see "Cyber Range interconnected environments" below,
      ADR 0023). 57 unit tests for the original single-host command set
      (path resolution/implicit directories + every command's real and
      error-path behavior) plus 13 more for `ssh`/`exit`'s multi-host
      behavior
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
- [x] Cyber Range interconnected environments — `EnvironmentSpec` gained
      `hosts`/`reachable_hosts` (additively, every pre-existing single-host
      lab keeps working unchanged), and two new terminal commands: `ssh
      <user>@<hostname> <password>` (gated by real network-topology
      reachability AND a genuine credential match found by the learner
      elsewhere on the host, e.g. via `cat`/`grep` — never just "knowing a
      hostname") and `exit`/`logout` (restores the exact suspended session
      a pivot left). One real seeded lab, "Cyber Range: Lateral Movement to
      the Database Host," proves it end to end: a leaked cron-job
      credential on one host is the only way to reach a flag that exists
      only on a second. See ADR 0023.

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
- [x] "Ask Mentor" deep link from an investigation — `MentorContextType`
      gained an `investigation` value
      (`supabase/migrations/20260922000021_mentor_investigation_context.sql`),
      `buildFocusDetail()` grounds it in the real `investigations.title`/
      `briefing`, and `/investigate/[investigationId]` links to
      `/mentor?contextType=investigation&contextId=...`, mirroring the
      existing lab/CTF/lesson deep links. The `MODE: GUIDE_INVESTIGATION`
      prompt instructions already existed and needed no change — only the
      context type and the link were missing
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
- [x] Blue/Purple Team scenario linkage — two plain junction tables
      (`investigation_labs`/`investigation_ctf_challenges`, mirroring
      `capstone_labs`'s shape: publicly readable, staff-write only) link an
      investigation to the red-team lab(s)/CTF challenge(s) whose attack
      it's the blue-team side of. Admin tagging UI on
      `/admin/investigations/[id]`; a "Purple Team" banner on
      `/investigate/[id]` links forward to the attack, and the same banner
      on `/labs/[id]`/`/ctf/[id]` links back to the investigation. One real
      seeded pairing, not just schema: "Purple Team: Detecting the Database
      Lateral Movement" is the literal blue-team side of the Cyber Range
      lateral-movement lab above — same leaked credential, same hosts, an
      auth log with the exact off-schedule login a SOC analyst has to
      catch. See ADR 0024.

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
- [x] Arena/mission UI (CTF timers/leaderboard) — `ctf_events` and
      `ctf_challenges.event_id` already existed with real RLS; nothing had
      ever built the UI for them. `/admin/ctf-events` authors events
      (title/slug/scoring type/start-end window/publish) and challenges
      can be assigned to one. `/ctf` groups published events (live status
      badge: upcoming/live/ended) above independent challenges;
      `/ctf/events/[eventId]` has a ticking countdown and a real
      leaderboard (`ctf_event_leaderboard()`, a `SECURITY DEFINER`
      function returning only the cross-user aggregate -- never which
      challenges a rival solved -- ranked by points desc, ties broken by
      earliest last-solve). `ctf_scoring_type='dynamic'` remained inert at
      this point (disclosed in the admin UI itself, not silently ignored)
      -- decaying scoring was a separate feature touching a grading
      function and got its own design pass later; see ADR 0021/0062.
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
- [x] EXPLAIN_FINDING is real: this entry had gone stale (it said "the
      scanner ... [doesn't] exist yet," true when first written but not
      since the scanner shipped). `MentorContextType` gained a `finding`
      value
      (`supabase/migrations/20260922000022_mentor_finding_context.sql`),
      `buildFocusDetail()` grounds it in the caller's own real
      `scan_findings` row (category/severity/evidence/explanation/impact/
      remediation, RLS-scoped the same as every other table here), and
      each finding's "Details" panel now has an "Ask Mentor" link. 2 new
      unit tests assert the mode actually uses this real data and that
      neither `review_report` nor `review_methodology` claims the
      scanner itself is unimplemented.
- [x] REVIEW_REPORT / REVIEW_METHODOLOGY are real: `/reports` lets a
      learner write a pentest report or methodology write-up
      (`reports` table, owner-only RLS mirroring `mentor_conversations`),
      `'report'` is a real `MentorContextType`
      (`20260922000025_reports.sql`), and both modes now actually critique
      the user's own real report/write-up (structure, whether each claim
      is backed by evidence, what's missing) instead of the old
      disclaimer. Deliberately separate from a capstone's staff-reviewed
      `report_content` (ADR 0008) — this is Mentor-only practice, never
      graded, no skill_evidence. While wiring this up, found and fixed a
      real, separate bug: `explain_finding`/`guide_investigation` already
      had working prompt logic and API support but were unreachable from
      the UI (`mentor-chat.tsx`'s mode picker only ever offered 4 generic
      modes, and nothing derived a context-appropriate default) — fixed
      with a new `lib/mentor/modes.ts` (`defaultModeForContext()`,
      `extraModesForContext()`, and a single `ALL_MENTOR_MODES` list
      replacing a hand-maintained copy in the API route) and explicit
      `&mode=` on every "Ask Mentor" deep link. See ADR 0020.
- [x] AI-assisted reasoning layer for the security scanner — this entry
      was a stale duplicate (it said "waits on the scanner itself, not
      started," but the scanner and its AI enrichment layer both shipped
      earlier in this session). See "AI-assisted enrichment layer" under
      Security scanning engine below for the real, tested implementation.
- [x] Response streaming: `POST /api/mentor/chat` now returns a
      `ReadableStream` of newline-delimited JSON events (`delta`/`done`/
      `error`) instead of one JSON blob, using the Anthropic SDK's
      `messages.stream()` + `.on('text', ...)` — the Mentor's reply
      renders token-by-token in `mentor-chat.tsx` as Anthropic produces
      it, not after the full response completes. DB persistence
      (`mentor_messages`, audit log) still happens once, after the stream
      completes, using the accumulated final text via `.finalMessage()` —
      not per-token. The NDJSON parsing itself is pure and unit-tested
      (`lib/mentor/ndjson.ts`, 7 assertions) independent of any real
      stream/network mock.

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

- [x] `/reports`: write a pentest report or methodology write-up, ask the
      AI Mentor to review it (REVIEW_REPORT/REVIEW_METHODOLOGY — see the
      AI Security Mentor section above and ADR 0020). Owner-only RLS,
      real delete (nothing else references a report's id). This is
      Mentor-reviewed practice, not a graded submission — a human-reviewed
      report within a graded project is the capstone flow
      (`capstone_submissions.report_content`, ADR 0008), which already
      existed and is unchanged by this.

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
      violation. See `docs/adr/0012-account-deletion.md`. A related,
      separately-discovered gap — `subscriptions.subject_id` (polymorphic,
      so it can't carry a normal FK at all) leaving orphaned subscription
      rows behind on deletion — was found and fixed afterward; see
      `SECURITY_AUDIT.md` AUDIT-010.
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
- [x] Documented retention policy — `DATA_RETENTION.md`, a per-table-category
      breakdown (owned data deleted via CASCADE, attribution nulled, the
      audit log and staff-authored content retained indefinitely with a
      stated reason why, `login_attempts`' 15-minute self-expiry, and the
      subscription-cleanup triggers from AUDIT-010), including an honest
      "not yet configured" for backups (no real Supabase project exists)
      and a called-out limitation in `billing_webhook_events`' raw payload
      retention rather than leaving it undocumented

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
- [x] Actually observed green on a real GitHub Actions run: it wasn't,
      for several pushes, and local verification alone had missed it --
      this item stayed unchecked specifically so it would get checked
      for real rather than assumed. Checking the Actions tab (now
      possible with this session's GitHub access) surfaced two genuine
      CI-only failures neither local run had caught:
      1. `flutter analyze` exits 1 on ANY issue, including the two
         `deprecated_member_use` infos `learn_screen.dart` (ADR 0060)
         had carried since that phase -- I'd read "2 issues found" as
         harmless because they were info-severity, but never actually
         checked the process exit code locally, which is exactly what
         CI's workflow step checks. Fixed by wrapping that screen's
         quiz-choice `RadioListTile`s in a `RadioGroup` ancestor, the
         same non-deprecated pattern `exam_attempt.dart` already used
         (verified: `flutter analyze` now prints "No issues found!" and
         exits 0).
      2. `gitleaks/gitleaks-action@v2` now refuses to run on an
         organization-owned repo without a paid `GITLEAKS_LICENSE`
         secret -- it exited before scanning anything, on every push.
         Replaced with the open-source `gitleaks` CLI (still MIT-licensed;
         only the hosted Action wrapper added the license gate) installed
         and run directly, pinned to v8.30.1, no new secret needed.
         Verified by building that exact version from source in this
         sandbox and running `gitleaks detect --source . --redact
         --no-banner` against the real repo history: exit 0, no leaks.
      Every other CI job (Lint & Typecheck, Unit Tests, DB Migrations &
      RLS Regression Tests, Build (Next.js), E2E Smoke Tests) was already
      genuinely green on every one of those pushes -- only these two.
      Confirmed on the real run this fix's own push triggered (run
      #106, commit `7a8c436`): all 7 jobs completed with conclusion
      `success`, watched live via the GitHub Actions API rather than
      assumed from the push succeeding.
- [ ] Deploy job (no hosting target connected yet — see `MANUAL_SETUP.md` §5)

## Testing

- [x] 191 SQL regression assertions across 26 files (`supabase/tests/`),
      verified in this sandbox by actually starting the local Postgres
      cluster and running `scripts/run-sql-tests.sh` against it (this
      count is a direct `grep -c "PASS:"` tally across every test file,
      not a hand-carried running total, since that had drifted slightly
      out of sync with the actual files in earlier phases): RLS + grading
      + entitlements + a full seeded-content walkthrough + org-instructor
      visibility + invitations + capstone review lifecycle + the seeded
      standalone exam + the real pro plan's entitlements + admin role
      management + org-scoped audit log coverage + account deletion + org
      member management + login rate limiting + subscription cleanup on
      user/org deletion + announcements read/write visibility across
      staff/instructor/member/outsider + their ownership/attribution FK
      behavior + reports owner/staff/outsider visibility and the report
      mentor-context type + the CTF event leaderboard's ranking/tie-break/
      draft-event guard + Blue/Purple Team scenario linkage RLS and the
      real seeded pairing + announcement translations' RLS (mirroring the
      parent announcement's visibility exactly), uniqueness, and cascade
      delete (new this phase, see ADR 0038)
- [x] 316 unit tests (validation logic, env guards, UI components including
      the Prove Your Skill matrix's evidence-cell indicator, AI Mentor
      prompt safety including the EXPLAIN_FINDING/REVIEW_REPORT/
      REVIEW_METHODOLOGY grounding, Mentor mode-selection logic
      (`lib/mentor/modes.ts`), streaming NDJSON parsing, security scanner
      rule engine + enrichment prompt + status transitions, lab terminal
      path resolution + command interpreter + real-permission enforcement
      + multi-host ssh/exit pivoting + the seeded labs' solvability
      (including the new Cyber Range lab), live billing signature
      verification + request-building for Stripe/Paystack/Flutterwave,
      Turnstile verify-request/response logic, the learning-path
      import/export bundle schema, admin CMS form submission/pending/error
      behavior via mocked server actions, the CTF event status classifier,
      the i18n `translate()` fallback/interpolation logic and locale
      validation, `extractBearerToken()`'s `Authorization: Bearer <token>`
      parsing for the mobile API auth path, and — new this phase —
      `pickAnnouncementText()`'s default-locale/translated/fallback cases
      plus component tests proving the admin/org announcement forms'
      optional Spanish fields round-trip through `FormData` and clear
      correctly (ADR 0038))
- [x] 33 e2e smoke tests (public pages, auth wall across all protected
      sections including `/scanner`/`/orgs`/`/capstones`/`/exams`/
      `/reports`, an invite link's `?next=` round-trip, login error
      handling, the MFA step-up page's own auth wall, the path-import
      page's own auth wall, the admin announcements/ctf-events pages'
      own auth wall, the landing page linking a real web app manifest
      whose icon URLs actually return a 200 PNG, `/offline` rendering
      without requiring auth, a real click-through switching the landing
      page to Spanish, confirming it actually re-renders, reloading to
      confirm the choice persists via cookie, and switching back, and the
      same 401-not-redirect proof (a request with no auth at all, and one
      with a bogus `Bearer` token where relevant) across every Bearer-
      auth-wired mobile-facing route: `/api/mentor/chat` (ADR 0033),
      `/api/scanner/scan` (ADR 0035), `/api/labs/{id}/terminal`
      (ADR 0039), `/api/scanner/findings/{id}/enrich` (ADR 0045), and
      `/api/billing/checkout` (ADR 0047))
- [x] Component-level test coverage for a representative slice of admin CMS
      forms (14 tests: `admin/announcements` create+edit, including the
      optional Spanish translation fields (ADR 0038), the org-scoped
      `orgs/[orgId]/announcements` create form, and the original
      `admin/paths` create form) — `vi.mock()`s the "use server" actions
      module and asserts the real form component's own behavior: the
      `FormData`/bound-id it submits, pending-state button label/disabled
      attribute, and error rendering. See ADR 0018 for why this is a
      genuinely different (and narrower) claim than a real RLS-backed
      click-through: confirmed in this sandbox that neither the `supabase`
      CLI nor a reachable Docker daemon exist here, so that part remains
      blocked on a provisioned Supabase project, same as every other
      admin-CMS/org flow. The remaining CMS forms (labs, quizzes/
      questions, CTF, capstones, investigations, users, org member
      management) still have only the pattern to follow, not tests written
      against it yet.
- [x] Load/performance testing — two scripts, each honest about what it
      measures (see ADR 0019):
      `bash scripts/perf-test-sql.sh` seeds a real local Postgres (300
      users, with one user's `skill_evidence`/`scans` history deliberately
      grown to 300/800 rows amid the shared table) and runs
      `EXPLAIN (ANALYZE, BUFFERS)` on this app's actual hot, RLS-evaluated
      queries (dashboard, skills matrix, scanner list); gates on "no
      sequential scan on a table this test grew large" rather than an
      absolute millisecond budget, since this sandbox's hardware isn't
      representative of any real deployment. A run here: all 8 queries
      under 2ms, zero seq scans.
      `node scripts/perf-test-http.mjs` runs real concurrent HTTP load
      (hand-rolled, no new dependency) against a real `next start`
      production server's public pages (`/`, `/login`, `/signup` — the
      only ones that render without a live Supabase project); gates on
      zero request failures under load. A run here: 20 concurrent workers
      for 15s, 3675 requests, 0 failures (`/` p50=104ms/p95=142ms/
      p99=214ms; `/login` p50=91ms/p95=183ms/p99=290ms; `/signup`
      p50=31ms/p95=103ms/p99=204ms). While verifying this script, found and
      fixed a real bug in it: spawning via `npx next start` and cleaning up
      with a plain `.kill()` reliably killed `npx` but orphaned the actual
      `next-server` process (reparented to pid 1, left running indefinitely
      holding the port) — fixed by spawning the local `next` binary
      directly in its own process group and killing the whole group, with
      a SIGKILL fallback (see ADR 0019). Neither script is wired into CI —
      deliberately manual, see ADR 0019. A real load test against
      authenticated, database-backed routes still needs a provisioned
      Supabase project, the same limitation as everything else in this
      sandbox.

## Production readiness

- [ ] Real Supabase project provisioned (`MANUAL_SETUP.md` §2)
- [ ] Deployment target connected (`MANUAL_SETUP.md` §5)
- [ ] Domain configured (`MANUAL_SETUP.md` §6, optional)
- [ ] Production environment variables set (`MANUAL_SETUP.md` §2a, §7)

## Mobile readiness

- [x] Backend contracts (Postgres schema + RPC functions) kept independent
      of Next.js-specific code, so a Flutter client can call the same
      Supabase project directly
- [x] Flutter app scaffolded (`mobile/app`) with a real, working auth flow:
      sign up (same 12-char/upper/lower/digit password policy as
      `apps/web`), log in, log out, session persisted across restarts,
      via `supabase_flutter` against the same Supabase project. A
      `--dart-define`-configured app fails with a real, clear
      "not configured" screen rather than crashing or using mock data --
      see `mobile/app/README.md`. See ADR 0026.
- [x] Five bottom-nav tabs plus three more screens behind a "More" menu
      (restructured off a flat, growing tab bar -- see ADR 0032): a
      Home/dashboard tab (display name, real active plan or "Free", up
      to 5 active announcements); Labs (published labs, start
      guided/unguided, unlock hints, a real flag submit through
      `submit_lab_flag()`, and, for terminal-backed labs, a real
      interactive terminal via a Bearer-authenticated
      `/api/labs/{id}/terminal` -- the same server-side interpreter and
      multi-host ssh/exit pivoting `apps/web` uses; command-history
      recall is web-only, named as a real gap rather than silently
      missing. See ADR 0039/0040.); a skills
      list (`skills` + `user_skill_states`, the same tables/RLS `/skills`
      and its SQL tests already prove) with the identical 7-state label
      vocabulary as `components/skill-state-badge.tsx`; CTF challenges
      (`ctf_challenges_public` + a real flag submit through the same
      `submit_ctf_flag()` RPC `apps/web` calls -- correctness is never
      decided client-side on mobile either); and, behind More: Investigate
      (real evidence artifacts, a mixed multiple-choice/exact-text answer
      form graded server-side via `submit_investigation_answers()`, and a
      private debounced-autosave notes scratchpad), Exams (a real
      countdown timer, single/multi-choice answers, grading exclusively
      through `submit_quiz_attempt()` -- same client-side-timer
      limitation as the web app, not a new gap), Capstones (skill/lab
      tag chips, submission history with reviewer notes, a plain
      `capstone_submissions` report insert -- no RPC exists for this,
      matching the web app), AI Mentor (general-chat modes only --
      Explain/Hint/Teach/Analyze a failure, no lab/lesson/finding deep
      links yet -- streaming the real NDJSON `/api/mentor/chat` response
      token-by-token via a ported `parseNdjsonLines()`, authenticated with
      a Bearer token instead of a cookie; degrades to a plain "not
      configured" message if the optional `API_BASE_URL` build value is
      unset, same pattern as web's Turnstile/billing. See ADR 0034.), and
      the Security Scanner (past scans + a combined posture summary, a
      "New scan" screen that pastes a single snippet or picks one or
      more real files (`file_picker`, the one new dependency outside
      `http`/`supabase_flutter` -- see ADR 0048) and submits via the
      same Bearer-token path to `/api/scanner/scan`, and a scan-detail
      screen with severity-coded findings, real manual status-transition
      buttons (`transition_scan_finding_status()` RPC, plain RLS-scoped,
      no Route Handler -- see ADR 0044), and a real "Enrich with AI"
      button against the now Bearer-authed
      `/api/scanner/findings/{id}/enrich` -- no named gaps remain on
      this screen. See ADR 0036/0044/0045/0048.),
      and Billing (real plan/status/entitlements from
      `subscriptions`/`plans`/`plan_entitlements`, plain RLS-scoped
      Postgrest, no Route Handler needed for any of that, plus a real
      "Upgrade with Stripe/Paystack/Flutterwave" flow against a new
      Bearer-authed `/api/billing/checkout` -- same provider calls as
      the web app's own checkout actions, hands back the hosted checkout
      URL via a copy-link dialog rather than a WebView, since this app
      never touches card details either way; canceling/managing an
      existing subscription isn't built on either client -- same
      provider-dashboard-self-service design as checkout itself. See
      ADR 0037/0047.)
- [x] `flutter analyze` clean, 226 `flutter test`s passing, `flutter build
      web` succeeding both with and without `--dart-define=API_BASE_URL=...`
      (verified in a sandbox with no Android SDK/Xcode/GTK -- see
      ADR 0026); wired into CI (`.github/workflows/ci.yml`'s `mobile` job,
      which now builds both configurations)
- [x] Bearer-token API auth for Route Handlers a mobile client calls
      directly, not just Postgrest/RPC: `requireApiUser(request)`
      (`lib/auth/api.ts`) accepts an `Authorization: Bearer
      <supabase_flutter session.accessToken>` header, verified with the
      explicit `supabase.auth.getUser(token)` form, and returns the same
      RLS-scoped (never `service_role`) client either caller gets --
      falls straight through to the existing cookie-session path when no
      such header is present, so `apps/web`'s own behavior is unchanged.
      Wired into `/api/mentor/chat` in place of `requireUser()` +
      `createClient()`. See ADR 0033. Also wired into
      `/api/scanner/scan` (the scan-submission route the mobile Scanner
      screen calls). See ADR 0035. Also wired into
      `/api/scanner/findings/[findingId]/enrich` (the enrichment route
      the mobile Scanner's "Enrich with AI" button calls). See ADR 0045.
      Also wired into `/api/labs/[labInstanceId]/terminal` -- the lab
      terminal command route the mobile terminal screen calls. See
      ADR 0039. Also wired into a new `/api/billing/checkout` (the
      checkout-session route the mobile Billing screen's "Upgrade"
      buttons call). See ADR 0047. Also wired into a new
      `/api/admin/labs/[labId]/environments` (validates a submitted
      terminal environment spec against `environmentSpecSchema` before
      the admin Labs screen's "Save environment" button upserts it). See
      ADR 0057.
- [x] Interactive lab terminal on mobile: `Open terminal` on a started,
      terminal-backed lab instance pushes a real terminal screen that
      POSTs each command to `/api/labs/{id}/terminal` with a Bearer token
      -- the exact same server-side interpreter and multi-host ssh/exit
      pivoting `apps/web`'s own `terminal.tsx` calls, no logic
      re-implemented client-side. Closes the last "not on mobile yet" gap
      this app named for labs since ADR 0026. See ADR 0040. (Command-
      history recall, originally scoped out here as impossible on a
      touch keyboard, was corrected and built for real in ADR 0050 below
      -- a hardware/arrow-key-capable keyboard sends real key events the
      on-screen keyboard just doesn't have.)
- [x] Organizations on mobile: real memberships, a "Create organization"
      flow (a plain insert -- the existing `handle_new_organization`
      trigger makes the creator its `team_owner`), the member roster
      (admins can change roles/remove members via the real
      `update_organization_member_role()`/`remove_organization_member()`
      RPCs; anyone can leave), and, for admins, a real invite-link flow
      (`create_organization_invitation()`) with revoke -- plain RLS-
      scoped Postgrest/RPC, no Route Handler needed. See ADR 0041.
- [x] Instructor dashboard on mobile: for any instructor/team_owner/
      org_admin, real per-member graded results (skills proven/in
      progress, labs completed, quizzes passed, CTF solved,
      investigations passed) -- the exact same six RLS-scoped queries
      `apps/web`'s own dashboard runs, aggregated via a ported, unit-
      tested `computeMemberStats()`, rendered as one card per member
      rather than the web's 8-column table (no room for that on a
      phone). Reachable from the Organizations screen once you're an
      instructor of an org. See ADR 0042.
- [x] Org announcement authoring on mobile: for that same
      instructor/team_owner/org_admin, a real
      list/create/edit/publish-toggle/delete screen against the same
      `announcements` table and `announcements_write` RLS the web CMS
      uses -- plain RLS-scoped Postgrest, no Route Handler, no new RPC.
      Closes ADR 0041's last named Organizations gap. See ADR 0043.
- [x] Spanish translation authoring on the mobile org announcement form:
      an optional "Spanish translation" section (title/body) using the
      exact same both-fields-or-neither upsert-or-delete rule as
      `upsertSpanishTranslation()` (`announcement_translations`,
      ADR 0038), ported as a pure `shouldUpsertSpanishTranslation()`
      helper. Closes ADR 0043's named gap. See ADR 0046.
- [x] Manual finding-status transitions on the mobile Scanner: the
      `transition_scan_finding_status()` RPC, plain RLS-scoped, no Route
      Handler, wired straight into the scan-detail screen's finding
      cards -- a status chip plus one button per legal next status,
      LEGAL_TRANSITIONS/labels ported as plain Dart consts from
      `status-transitions.ts`/`finding-status-badge.tsx`. Narrows ADR
      0036's Scanner gap to just AI enrichment and multi-file upload. See
      ADR 0044.
- [x] "Enrich with AI" on the mobile Scanner: `requireApiUser()` wired
      into `/api/scanner/findings/[findingId]/enrich` (same pattern as
      Mentor/scan-submission/the lab terminal), and a real button on the
      scan-detail screen calling it with the session's Bearer token,
      shown only when `AppEnv.isApiConfigured`. Narrows ADR 0036's
      Scanner gap down to just multi-file upload. See ADR 0045.
- [x] Multi-file upload on the mobile Scanner's "New scan" screen: a
      "Choose files" button (`file_picker: ^8.1.7`, the one new
      dependency outside `http`/`supabase_flutter`, since there's no
      SDK-only way to open a real file/browser picker) reads one or more
      real files as text and submits them as `targetType:
      "uploaded_files"` -- a shape `/api/scanner/scan`'s requestSchema
      already accepted, so this was purely a mobile UI gap, not a server
      change. Pure `buildScanRequestBody()` decides pasted-snippet vs
      uploaded-files shape, unit-tested without needing a real picker.
      Closes ADR 0036's last named Scanner gap -- no gaps remain on that
      screen. See ADR 0048.
- [x] Real checkout on the mobile Billing screen: a new Bearer-authed
      `/api/billing/checkout` runs the exact same provider calls as the
      web app's own `createXCheckoutAction()`s and returns the hosted
      checkout URL as JSON instead of redirecting; "Upgrade with
      Stripe/Paystack/Flutterwave" buttons call it and show the URL via
      a copy-link dialog, the same pattern as the Organizations screen's
      invite link, never a WebView. Closes the checkout half of ADR
      0037's Billing gap; canceling/managing an existing subscription
      isn't built on either client -- same provider-dashboard-self-
      service design as checkout, not a gap. See ADR 0047.
- [x] First staff Admin screen on mobile: `lib/auth/roles.dart`'s
      `fetchUserRoles()`/`isStaffRole()` mirror `is_staff()` (admin or
      moderator) to gate a new "Admin" entry in the More screen; today
      it holds one real flow, Platform Announcements -- the
      `organization_id IS NULL` twin of the Organizations screen's own
      announcement CRUD, reusing the same `OrgAnnouncement` model and
      pure helpers, plus the `log_audit_event()` RPC call on publish/
      unpublish the web admin action itself makes (the org-scoped
      action and screen don't make that call). See ADR 0049.
- [x] Command-history recall (up/down arrow) on the mobile terminal: a
      `Focus` wrapping the input field intercepts real hardware
      ArrowUp/ArrowDown key events (a Bluetooth/USB keyboard, or a
      software keyboard app that draws its own, e.g. Hacker's Keyboard
      -- the stock on-screen keyboard alone has none) before `TextField`'s
      own default shortcuts can -- verified for real with
      `tester.sendKeyEvent()`, not just inferred. Pure
      `recallTerminalHistory()` ports `terminal.tsx`'s own logic exactly,
      including its ArrowDown-while-idle-clears-input quirk. Retracts
      the earlier "impossible on a touch keyboard" framing (ADR 0040,
      this file, both READMEs) as wrong -- real for the subset of users
      with such an input method. See ADR 0050.
- [x] Admin Users (role management) screen on mobile: search any user
      (`admin_search_users()`) and grant/revoke their instructor/
      moderator/admin roles (`grant_platform_role()`/
      `revoke_platform_role()`), each already audit-logging and
      re-checking `is_admin()` itself server-side -- no new client-side
      authorization logic needed beyond the Admin section's existing
      `isStaffRole()` gate. Optimistic toggle with revert on failure,
      same as `role-toggle.tsx`; can never revoke your own admin role.
      See ADR 0051.
- [x] Reports screen on mobile: list/create/edit/delete for the
      pentest-report/methodology-write-up pillar -- plain RLS-scoped
      Postgrest CRUD on `reports`, no Route Handler needed. Corrects an
      earlier mislabel in this file ("report moderation") -- Reports has
      no reviewer role at all; it's reviewed by the AI Mentor only and
      had simply never been ported, unlike the Scanner/Billing/
      Organizations gaps closed earlier. "Ask Mentor to review" opens
      the general-mode Mentor screen rather than a true deep link into
      `review_report`/`review_methodology` -- narrows ADR 0034's Mentor
      deep-link gap to specifically include `report`, not a new gap.
      See ADR 0052.
- [x] Admin CTF Challenges + CTF Events screens on mobile: create/edit for
      both, plain RLS-scoped Postgrest CRUD on their `is_staff()`-gated
      tables, no Route Handler and no new backend surface at all. A new
      flag is hashed to lowercase hex SHA-256 on-device with
      `package:crypto` (now a direct dependency, previously transitive
      only) the moment it's submitted -- byte-identical to `apps/web`'s
      own server-side `hashFlag()`, verified against two known digests --
      never stored or shown as plaintext again. Challenges get publish
      toggles, an inline skill tagger (`ctf_challenge_skills`), and an
      event dropdown; events get publish toggles, optional start/end
      times, and a read-only list of their own challenges. No delete
      action on either, matching the web admin UI. See ADR 0053.
- [x] Admin Quizzes screen on mobile: create (no edit form for a quiz's
      own fields -- the web admin UI doesn't have one either, only a
      publish toggle, skill tagger, and questions manager once a quiz
      exists), a publish toggle, an inline skill tagger
      (`quiz_skills`), and a questions manager that only ever creates
      `single_choice` questions with a growable choice list (the same
      restriction `questions-manager.tsx` has), validated the same way:
      at least two non-empty choices after trimming, at least one marked
      correct. Plain RLS-scoped Postgrest CRUD on `quizzes`/
      `quiz_questions`/`quiz_choices`/`quiz_skills`, no Route Handler.
      See ADR 0054.
- [x] Admin Learning Paths screen on mobile: create/edit a path (title/
      slug/description, publish toggle), create modules under it (no
      module edit form -- the web admin UI doesn't have one either, only
      a publish toggle and its own lessons), and create/edit lessons
      under a module (title/slug/summary/content/estimated minutes,
      publish toggle, and an inline skill tagger for `lesson_skills`
      with the same "feeds the Skill Graph" note the web page shows).
      `order_index` stays at its schema default (0) on every insert, same
      as the web, which has no reordering control anywhere either. Plain
      RLS-scoped Postgrest CRUD on `learning_paths`/`modules`/`lessons`/
      `lesson_skills`, no Route Handler. Path import/export is a separate
      gap, not attempted here. See ADR 0055.
- [x] Admin Labs screen on mobile: create/edit (title/slug/category/
      difficulty/minutes/points/description, publish toggle, inline
      skill tagger for `lab_skills`), a hints manager (level 1-5, point
      cost, add/remove against `lab_hints`), and a flags manager (label,
      variant seed, a plaintext field hashed to lowercase hex SHA-256
      on-device with the same `hashCtfFlag()` ADR 0053 built, add/remove
      against `lab_flags`). Plain RLS-scoped Postgrest CRUD throughout,
      no Route Handler for the lab's own fields/skills/hints/flags. See
      ADR 0056.
- [x] Terminal environment editor on mobile, closing ADR 0056's named
      gap: existing environments list/load-into-editor/remove via plain
      Postgrest (`lab_environments_staff_only` is staff-read too, not
      just staff-write), and a variant-seed-plus-JSON-spec form whose
      "Save environment" button calls the new
      `/api/admin/labs/[labId]/environments` Route Handler instead of
      writing directly -- it re-validates the spec against
      `lib/terminal/spec.ts`'s `environmentSpecSchema` (the same schema
      `lib/terminal/execute.ts` parses it with) before upserting, so the
      two clients can never save a spec under different rules; RLS is
      still the real authorization boundary underneath it, same as a
      direct write would get. 34 e2e tests now (was 33). See ADR 0057.
- [x] Path import/export on mobile, closing the last named `/admin/*`
      gap: an "Export" button on a path's detail screen GETs a new
      Bearer-authed `/api/admin/paths/{pathId}/export` (moved there from
      its original `/admin/paths/{pathId}/export` after the new e2e test
      for it caught a real bug -- `/admin` is one of the web app's
      proxy-level protected prefixes, which redirects an unauthenticated
      *browser* request to `/login` using only the cookie session, before
      any Route Handler under it runs, with no knowledge of a Bearer
      header; a mobile caller would always have been redirected to an
      HTML login page instead of ever reaching this route's own
      `requireApiUser()` 401) and shows the bundle JSON in a
      copy-to-clipboard dialog, same pattern as the Organizations
      screen's invite link. An "Import a path" button opens a paste-JSON
      screen that POSTs to a new `/api/admin/paths/import`, a JSON
      adapter around `importPathBundle()` -- the exact multi-step
      insert-with-rollback orchestration extracted out of
      `importPathBundleAction` into
      `lib/content-io/import-path-bundle.ts` so the web Server Action and
      this new Route Handler share one implementation, never two. 36 e2e
      tests now (was 34); `tsc --noEmit`, ESLint, `npx vitest run` (316
      tests, unchanged), and `npm run build` all pass. See ADR 0058.
- [x] Mentor context-specific deep links on mobile: `/api/mentor/chat`
      and `buildMentorContext()` already supported `explain_finding`/
      `guide_investigation`/`review_report`/`review_methodology` server-
      side -- the gap was purely that `MentorScreen` hard-coded
      `contextType: 'general'` and offered only a four-mode picker.
      `MentorMode` extended to all eight real modes;
      `defaultModeForContext()`/`extraModesForContext()`/
      `modesForContext()` ported from `lib/mentor/modes.ts`; a "Mentor"
      button added to the Lab detail, CTF challenge detail, and
      Investigation detail screens, and to the Scanner's finding cards;
      Reports' existing "Ask Mentor to review" button (ADR 0052) now
      passes the report's real context and kind-based mode instead of
      opening the general-mode screen with none. In passing, fixed a
      stale in-app banner on the Lab detail screen still claiming
      terminal command-history recall was "web-only" after ADR 0050
      corrected that everywhere else. Named, not silently carried
      forward: the `lesson` context had no mobile entry point yet
      because there was no mobile learner-facing lesson/path viewer to
      attach one to (closed next, see below), and reopening any
      context's chat always starts a fresh conversation rather than
      resuming the last one for that context, the same pre-existing
      limitation general-mode Mentor already had. +6 `flutter test`s
      (194 total, was 188). See ADR 0059.
- [x] Learner-facing Learning Paths viewer on mobile: a new "Learn" entry
      in "More" lists published paths, then modules grouped with their
      published lessons (a "Read" tag once `lesson_progress.completed_at`
      is set for that lesson, else its estimated minutes), then a lesson
      viewer that upserts `lesson_progress` on open (mirroring
      `mark-read.tsx`'s own "once per mount" guard -- `lesson_progress_own`
      RLS is the real enforcement either way), shows the lesson's
      `content_markdown` as plain text (no markdown-rendering package
      exists anywhere in this app yet -- every other `*_markdown` field,
      including the learner-facing dashboard's own announcements, renders
      the same way, so this stays consistent rather than introducing the
      app's first one), and, when a published quiz is linked via
      `quizzes.lesson_id`, embeds it right there, grading through the
      real `submit_quiz_attempt()` RPC -- same single-choice-only-even-
      for-`multi_choice` limitation and same no-`order_index`-sort of its
      questions `quiz-attempt.tsx` has on web, not a mobile gap. A
      "Mentor" button on the lesson viewer finally gives ADR 0059's
      `lesson` context deep link somewhere to attach -- no named Mentor
      context remains missing a deep link anywhere on mobile. Plain
      RLS-scoped Postgrest/RPC throughout, no Route Handler. +6
      `flutter test`s (200 total, was 194); `flutter analyze` clean;
      `flutter build web` succeeds both with and without `API_BASE_URL`.
      See ADR 0060.
- [x] Mentor conversation resume on mobile: checked whether "resume" is
      real backend behavior before accepting it as a permanent web/
      mobile divergence -- it isn't. `/api/mentor/chat` never upserts a
      conversation by context (a POST with no `conversationId` always
      inserts a new `mentor_conversations` row; there's no unique
      constraint on `(user_id, context_type, context_id)` either),
      so "resume" is purely `/mentor/page.tsx`'s own page-load lookup
      (most-recently-updated conversation for this user+context, then
      its `mentor_messages` in order) handed to the chat component as
      props. Ported that exact lookup into `MentorScreen.initState()`
      against the same `*_own`-RLS-scoped `mentor_conversations`/
      `mentor_messages` tables, no Route Handler. No new `flutter
      test`s (a stateful-widget lifecycle method against live
      Postgrest, same untestable-without-mocking shape `_send()`
      already had) -- 200 total, unchanged; `flutter analyze` clean;
      `flutter build web` succeeds both configs. No named Mentor gap
      remains anywhere on mobile. See ADR 0061.
- [x] Dynamic CTF scoring: `ctf_scoring_type='dynamic'` had been inert
      since the Arena/mission UI phase (above) -- picking it on an event
      stored the intent but `submit_ctf_flag()` always awarded the flat
      `points` value regardless. Checked `ctf_event_leaderboard()` first:
      it already sums each solve's own frozen `points_awarded`, the
      correct CTFd-style contract, so only the one place still computing
      a flat value needed to change. New `ctf_challenges.min_points`
      column (decay floor, NULL defaults to half of `points`) and new
      `ctf_challenge_current_points()` function -- independent challenges
      and static-scoring events always return the flat `points`; a
      dynamic-scoring event's challenge decays linearly from `points` to
      its floor over its first 10 solves, then stays flat. Both
      `ctf_challenges_public` (new `current_points` column, appended
      after the existing ones since `CREATE OR REPLACE VIEW` can't
      reorder) and `submit_ctf_flag()` call this same function, so the
      learner-facing display and the grading function can never
      disagree; the solve count the Nth solver sees is computed BEFORE
      their own `INSERT`, so the first solver always gets the full
      value. Web: admin challenge form gained a Min points field
      (validated `<= Points`), both admin event forms' "not implemented
      yet" disclaimers rewritten to explain the real behavior, and the
      challenge/event detail pages now display `current_points` with a
      "(decaying)" note when it differs from `points`. Mobile: the same
      Min points field on the admin challenge form, the same disclaimer
      rewrite on the admin event form, and both the flat CTF list and
      challenge detail screen display `current_points`. New migration
      `20260922000031_ctf_dynamic_scoring.sql` + SQL regression test
      `027_ctf_dynamic_scoring.sql` (6 assertions, run against the full
      migration chain locally: all pre-existing SQL tests still pass
      too). Web: `tsc --noEmit`/ESLint clean, `npx vitest run` unchanged
      at 316 tests (the new logic lives in SQL, tested there), `npm run
      build` succeeds, the 9 pure-HTTP "mobile API auth" e2e tests still
      pass (no Route Handler touched). Mobile: +2 `flutter test`s (202
      total, was 200); `flutter analyze` clean; `flutter build web`
      succeeds both configs. Auditing this surfaced a real, previously
      undocumented mobile gap named below rather than folded in here: no
      learner-facing CTF Events/leaderboard screen exists on mobile at
      all. See ADR 0062.
- [x] A learner-facing CTF Events/leaderboard screen on mobile: closes
      the gap named while auditing dynamic scoring's mobile parity
      (above) -- mobile's `/ctf` equivalent had only ever been the flat
      `ctf_challenges_public` list, with `ctf_events` read nowhere
      outside the admin screens. New `lib/ctf/ctf_event.dart`: a direct
      port of `lib/ctf/event-status.ts`'s `ctfEventStatus()` and
      `event-status-banner.tsx`'s `formatDuration()` (including its one
      real quirk -- once a duration is a day or more, seconds never show
      again, and minutes don't either if the hour component is exactly
      zero -- preserved, not "fixed"), plus `CtfEventSummary`/
      `CtfEventDetail`/`CtfLeaderboardEntry`. `ctf_list_screen.dart`
      rewritten to fetch published events alongside challenges, grouping
      independent challenges (`event_id IS NULL`) separately, same split
      `/ctf/page.tsx` has. New `ctf_event_detail_screen.dart`: the
      event's own challenges, the real `ctf_event_leaderboard()`
      aggregate with the signed-in user's own row highlighted, and a
      ticking status banner (a private `_EventStatusBanner` widget with
      its own 1s `Timer.periodic`, same component split as web's). Plain
      RLS-scoped Postgrest/RPC throughout, no Route Handler. +11
      `flutter test`s (213 total, was 202); `flutter analyze` clean;
      `flutter build web` succeeds both configs. No named mobile-vs-web
      gap remains anywhere in this app's CTF coverage. See ADR 0063.
- [x] Admin Learning Paths screen gains the same optional Spanish
      translation fieldset as the web admin CMS (ADR 0064) — the path
      form upserts/deletes `learning_path_translations`, the lesson form
      upserts/deletes `lesson_translations`, both re-using
      `shouldUpsertSpanishTranslation()`'s both-fields-or-neither rule
      for the lesson form and a title-only gate for the path form. Admin-
      authoring parity only, per the gap named directly below — this
      screen does not read any translation back either. No new
      `flutter test`s needed (no new pure logic); `flutter analyze`
      clean, `flutter test` passes (213 total, unchanged), `flutter
      build web` succeeds both configs. See ADR 0064.
- [x] Mobile locale-reading infrastructure — closes the gap named above:
      a new "Language" entry on the "More" menu (not folded into a
      Settings hub that doesn't otherwise exist on mobile) lets a
      learner pick English/Español, persisted on-device via
      `shared_preferences` (promoted from transitive to direct
      dependency — already used by `supabase_flutter` to persist the
      auth session, no new dependency) under the key `icorepen_locale`.
      New `lib/i18n/locale.dart` mirrors `lib/i18n/locales.ts` exactly
      (`supportedLocales`/`defaultLocale`/`isSupportedLocale()`,
      `LocaleStore.getLocale()`/`.setLocale()`). Three screens now read
      it back and apply the matching pick function, direct ports of
      their web namesakes: the Dashboard's announcements
      (`pickAnnouncementText()`), and Learn's path list, path detail
      (header + lesson list), and lesson viewer (`pickPathText()`/
      `pickLessonText()`). No new state-management dependency — each
      screen reads the stored locale once per load, the same per-request
      model web's own cookie read uses; a push-route screen (Learn's
      path/lesson detail) reloads fresh on every visit, while the
      Dashboard tab (kept alive in the bottom nav) picks up a changed
      locale on its existing pull-to-refresh. Still doesn't cover a
      Profile/Security/Privacy settings screen, since none of those
      exist on mobile yet — "Language" stands alone rather than implying
      a Settings hub that isn't there. +13 `flutter test`s (226 total,
      was 213); `flutter analyze` clean; `flutter build web` succeeds
      both configs. See ADR 0065.
- [ ] Everything else on mobile: no named mobile-vs-web gap remains
      anywhere in this app's feature set. This phase is a real vertical
      slice, not the whole web app's feature set, and is named as such
      rather than implied complete.
- [ ] A real Android/iOS build and a real device/emulator click-through
      -- not done here; this sandbox has no Android SDK or Xcode. Needs a
      machine with those toolchains, same "needs a provisioned
      environment this sandbox doesn't have" limitation as the web app's
      own remaining live-click-through items.
