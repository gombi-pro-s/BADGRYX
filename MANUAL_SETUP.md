# Manual Setup

Every step in this document requires **you** (or someone with access to the
relevant console/account) — Claude cannot create external accounts, click
through third-party consoles, or hold long-lived production credentials on
your behalf. Each item states exactly what to do, where, why, and how to
verify it worked.

Items are grouped by when you need them: **Local dev**, **Staging**, or
**Production**. Do local dev first — everything else builds on it.

---

## 1. GitHub access for Claude (blocks pushing this work)

**Required for**: any environment (this is why the current work is committed
locally but not yet pushed).

1. **What**: Grant the Claude GitHub App access to this repository, or
   reconnect your GitHub account to Claude.
2. **Where**: either
   - As an org admin: https://github.com/apps/claude/installations/select_target
   - Or reconnect from claude.ai: https://claude.ai/customize/connectors?auth_start=github&auth_start_force=1
3. **Exact value**: N/A — this is an authorization flow, not a value to enter.
4. **Why**: Without this, `git push` from this session fails with a 403 and
   no work can reach GitHub.
5. **Verify**: Ask Claude to push again, or run `git push` yourself from a
   machine with access — it should succeed.
6. **Expected result**: The branch `claude/repo-setup-from-scratch-e3x96t`
   appears on GitHub with the commits made so far.
7. **Required for**: Local dev is unaffected; this only blocks getting the
   work onto GitHub / into CI.

---

## 2. Create the Supabase project

**Required for**: Local dev, Staging, Production (one project per
environment is strongly recommended — do not share a production Supabase
project with local development).

1. **What**: Create a new Supabase project.
2. **Where**: https://supabase.com/dashboard → "New project".
3. **Exact value**: Pick a project name (e.g. `icorepen-dev` /
   `icorepen-staging` / `icorepen-prod`), a strong database password (save
   it in a password manager — you will need it for `supabase link`), and a
   region close to your users.
4. **Why**: This is the Postgres database + Auth + Storage backend the
   whole app is built against.
5. **Verify**: The project dashboard loads and shows "Project Settings" in
   the left sidebar.
6. **Expected result**: A project with a URL like
   `https://<project-ref>.supabase.co`.
7. **Required for**: all environments.

### 2a. Get your API keys

1. **What**: Copy the Project URL, `anon` public key, and `service_role`
   secret key.
2. **Where**: Project Settings → API.
3. **Exact value**: Copy `Project URL` → `NEXT_PUBLIC_SUPABASE_URL`; copy
   `anon` `public` key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`; copy
   `service_role` `secret` key → `SUPABASE_SERVICE_ROLE_KEY`.
4. **Why**: The anon key is safe for the browser (every table is
   RLS-protected); the service_role key **bypasses RLS entirely** and must
   only ever live in server-side environment variables (Vercel/hosting
   provider env vars, GitHub Actions secrets for deploy jobs) — never in
   `NEXT_PUBLIC_*`, never committed, never logged.
5. **Verify**: `apps/web/.env.local` has all three values filled in (see
   `apps/web/.env.example`).
6. **Expected result**: `pnpm dev` in `apps/web` starts without the
   "Missing required environment variable" error from
   `src/lib/supabase/env.ts`.
7. **Required for**: all environments.

### 2b. Apply the database schema

1. **What**: Push every migration in `supabase/migrations/` to the project.
2. **Where**: Your terminal (or a GitHub Actions deploy job — see §7).
3. **Exact value / commands**:
   ```bash
   pnpm dlx supabase login
   pnpm dlx supabase link --project-ref <your-project-ref>
   pnpm dlx supabase db push
   ```
4. **Why**: Without this, the app has no tables — every query will fail.
5. **Verify**: Table Editor in the Supabase dashboard shows `profiles`,
   `skills`, `labs`, `plans`, etc.
6. **Expected result**: `select count(*) from public.skills;` in the SQL
   editor returns `38` (the seeded skill catalog).
7. **Required for**: all environments.

### 2c. Configure Auth email templates and redirect URLs

1. **What**: Set the Site URL and allowed redirect URLs so
   signup-confirmation and password-reset emails link back to your app
   instead of `localhost` in production.
2. **Where**: Authentication → URL Configuration.
3. **Exact value**: Site URL = your `NEXT_PUBLIC_SITE_URL` (e.g.
   `https://app.icorepen.com` in production, `http://localhost:3000`
   locally). Add `<site-url>/auth/callback` to "Redirect URLs".
4. **Why**: `apps/web/src/app/auth/callback/route.ts` is what Supabase
   redirects the browser to after email confirmation, password reset, and
   OAuth — if it's not allow-listed, Supabase refuses the redirect.
5. **Verify**: Sign up with a real email in the deployed app; the
   confirmation link should land on your domain, not error out.
6. **Expected result**: Clicking the confirmation email link logs you in
   (or takes you to `/login`) without an "invalid redirect" error.
7. **Required for**: Staging, Production (local dev's default
   `http://localhost:3000/auth/callback` should already work once added).

### 2d. Decide on email verification requirement (optional but recommended)

1. **What**: Choose whether new signups must confirm their email before
   they can log in.
2. **Where**: Authentication → Providers → Email → "Confirm email" toggle.
3. **Exact value**: Enable it for Staging/Production; your call for local
   dev (disabling speeds up manual testing).
4. **Why**: Prevents throwaway/unverified accounts from using the platform.
5. **Verify**: Sign up with a test email; you should be unable to log in
   until you click the confirmation link (if enabled).
6. **Expected result**: Matches your chosen setting.
7. **Required for**: Staging, Production.

---

## 3. Anthropic API key (powers the AI Security Mentor)

**Required for**: the AI Mentor (`/mentor`, `POST /api/mentor/chat`) to
actually respond. Without this, every Mentor request fails with a 502
("The Mentor is temporarily unavailable") — the rest of the app is
unaffected. Not required for the (not-yet-built) AI-assisted security
scanner, which will reuse this same key once it exists.

1. **What**: Create an Anthropic API key.
2. **Where**: https://console.anthropic.com → API Keys.
3. **Exact value**: Copy the key into `ANTHROPIC_API_KEY` (server-only env
   var — never `NEXT_PUBLIC_*`; guarded by `lib/env.ts`'s `server-only`
   import the same way the Supabase service_role key is).
4. **Why**: Powers `lib/mentor/client.ts`, which calls the Anthropic
   Messages API (model: `claude-sonnet-5`) with a system prompt grounded
   in the user's real Skill Graph data (see
   `docs/adr/0007-ai-mentor-grounding.md`).
5. **Verify**: Log in, open `/mentor`, and send a message.
6. **Expected result**: A real response from Claude, referencing your
   actual skill states if you have any progress recorded. The daily
   request counter in the top-right of the Mentor chat should increment.
7. **Cost note**: Each Mentor plan's `ai_mentor_daily_requests` entitlement
   (10/day on the free plan — see `plan_entitlements` in
   `supabase/migrations/20260921000011_entitlements.sql`) is the only
   built-in cost control today. Watch usage in the Anthropic console while
   this is new, and lower the free-plan limit via that table if needed. The
   security scanner's deterministic rule engine (`POST /api/scanner/scan`)
   does not call this key at all today — no AI enrichment phase exists yet
   — but it is already rate-limited independently via `scanner_daily_scans`
   (5/day on the free plan — see
   `supabase/migrations/20260922000003_scanner_entitlements.sql`) so the
   same lever is ready once an AI-assisted enrichment layer is added.

---

## 4. Payment provider (deferred by design — see ADR 0005)

**Required for**: whenever you're ready to accept real payments. Not
required for anything currently built — the entitlement engine works today
with `provider = 'manual'` admin-granted plans.

When you're ready:

1. **What**: Create an account with your chosen provider (Stripe is the
   best-supported option for a Next.js app; Paystack/Flutterwave are
   better fits if your primary market is Africa).
2. **Where**: https://dashboard.stripe.com (or your chosen provider's
   dashboard).
3. **Exact value**: Create products/prices matching the rows you want in
   `public.plans`; get your secret key and webhook signing secret.
4. **Why**: Needed to actually charge customers; the current `plans`/
   `subscriptions` schema is designed so this is additive (see ADR 0005) —
   ask for this to be implemented once you have the account, and provide
   the API keys as environment variables at that time.
5. **Verify**: N/A until the webhook handler is implemented.
6. **Expected result**: N/A yet.
7. **Required for**: Production, once you want to charge money.

---

## 5. Deployment target

**Required for**: Staging, Production.

This app is a standard Next.js app and deploys to any Next.js-compatible
host (Vercel is the simplest for App Router + Server Actions).

1. **What**: Create a project on your chosen host, connect this GitHub
   repository, and set the root directory to `apps/web`.
2. **Where**: e.g. https://vercel.com/new
3. **Exact value**: Set the same environment variables as
   `apps/web/.env.example` (§2a values) in the host's project settings,
   scoped correctly: `NEXT_PUBLIC_*` can be "Production, Preview,
   Development"; `SUPABASE_SERVICE_ROLE_KEY` should be restricted to
   Production (and Preview only if you have a separate staging Supabase
   project for previews).
4. **Why**: This is how the app actually becomes reachable at a URL.
5. **Verify**: The deployed URL loads the landing page and `/login` works.
6. **Expected result**: A working deployment.
7. **Required for**: Staging, Production.

---

## 6. Domain and DNS (optional)

**Required for**: Production, if you want a custom domain instead of the
host's default subdomain.

1. **What**: Point your domain's DNS at your hosting provider.
2. **Where**: Your DNS provider + your hosting provider's "Domains" settings.
3. **Exact value**: Follow your hosting provider's exact instructions (they
   give you the CNAME/A records to add — these differ per provider and
   change over time, so there is no fixed value to print here).
4. **Why**: A custom domain for the production app.
5. **Verify**: `dig your-domain.com` resolves to your host; the site loads
   over HTTPS.
6. **Expected result**: `https://your-domain.com` serves the app.
7. **Required for**: Production (optional).

---

## 7. GitHub Actions secrets (for CI to use real Supabase values, optional)

**Required for**: Staging/Production CI jobs that need to talk to a real
Supabase project (e.g. a future deploy job, or if you want CI's build step
to catch config drift against real values instead of placeholders).

1. **What**: Add repository secrets matching your Supabase project.
2. **Where**: GitHub repo → Settings → Secrets and variables → Actions →
   "New repository secret".
3. **Exact value**: Add `NEXT_PUBLIC_SUPABASE_URL`,
   `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
   `NEXT_PUBLIC_SITE_URL` with the same values as §2a/§2c.
4. **Why**: `.github/workflows/ci.yml` falls back to harmless placeholder
   values when these secrets aren't set (so CI works out of the box without
   them), but real values let CI validate against your actual project
   config.
5. **Verify**: Re-run the CI workflow; the build job's env vars come from
   secrets instead of placeholders (check the job's env in the Actions log
   — GitHub automatically masks secret values).
6. **Expected result**: CI stays green.
7. **Required for**: optional; recommended once you have a real project.

---

## What's already handled without your action

- Local database testing (`scripts/run-sql-tests.sh`) needs no Supabase
  project — it uses a scratch local Postgres.
- CI (`.github/workflows/ci.yml`) runs lint/typecheck/unit tests/build/DB
  tests/security scan/e2e tests entirely with placeholder values where a
  real Supabase project isn't configured — you do not need to set up
  anything for CI to be useful from day one.
