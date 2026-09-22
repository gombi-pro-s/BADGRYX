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

**Required for**: the AI Mentor (`/mentor`, `POST /api/mentor/chat`) and the
security scanner's AI-enrichment step
(`POST /api/scanner/findings/[id]/enrich`) to actually respond. Without
this, every Mentor request fails with a 502 ("The Mentor is temporarily
unavailable") and every enrichment request fails with a 502 ("Enrichment is
temporarily unavailable") — the deterministic scan itself
(`POST /api/scanner/scan`) is unaffected either way, since it never calls
Anthropic.

1. **What**: Create an Anthropic API key.
2. **Where**: https://console.anthropic.com → API Keys.
3. **Exact value**: Copy the key into `ANTHROPIC_API_KEY` (server-only env
   var — never `NEXT_PUBLIC_*`; guarded by `lib/env.ts`'s `server-only`
   import the same way the Supabase service_role key is).
4. **Why**: Powers `lib/mentor/client.ts` (Mentor chat) and
   `lib/scanner/enrich.ts` (finding enrichment), both calling the Anthropic
   Messages API (model: `claude-sonnet-5`) with a system prompt grounded
   only in real data -- the user's Skill Graph for the Mentor
   (`docs/adr/0007-ai-mentor-grounding.md`), a specific finding's own
   evidence for the scanner (`docs/adr/0008-scanner-finding-lifecycle.md`).
5. **Verify**: Log in, open `/mentor` and send a message; separately, run a
   scan at `/scanner` (once built) and enrich a finding.
6. **Expected result**: A real response from Claude in both cases. The
   Mentor's daily request counter should increment; an enriched finding
   gets `ai_enriched = true` and updated explanation/impact/remediation
   text.
7. **Cost note**: Each feature has its own independent daily limit through
   the real entitlement engine, not a shared or unlimited budget:
   `ai_mentor_daily_requests` (10/day on free —
   `supabase/migrations/20260921000011_entitlements.sql`) for the Mentor,
   `scanner_daily_scans` (5/day on free —
   `supabase/migrations/20260922000003_scanner_entitlements.sql`) for
   running a scan, `scanner_daily_enrichments` (20/day on free —
   `supabase/migrations/20260922000004_scanner_enrichment.sql`) for AI
   enrichment calls on findings. Watch usage in the Anthropic console while
   this is new, and lower any of the three via `plan_entitlements` if
   needed.

---

## 4. Payment provider (checkout + webhook code is real; only your account/keys are missing)

**Required for**: accepting real payments. The checkout flow, webhook
handlers, and signature verification for Stripe, Paystack, and
Flutterwave are all fully implemented (see
`docs/adr/0011-live-billing-integration.md`) — until you complete this
section, `/settings/billing` simply shows each provider's upgrade button
as "not configured" and its webhook endpoint returns 503. The entitlement
engine works today regardless, with `provider = 'manual'` admin-granted
plans.

Configure as many of the three providers as you actually want to accept —
each is fully independent; none of this is required for the others to
work.

### 4a. Stripe

1. **What**: Create a Stripe account, a Product for the Pro plan, and a
   recurring monthly Price on it ($19/month to match the seeded `pro`
   plan's `price_cents`, or your own amount).
2. **Where**: https://dashboard.stripe.com → Product catalog → Add product.
3. **Exact value**: Copy the **Price ID** (starts `price_...`, not the
   Product ID) into `STRIPE_PRICE_ID_PRO`. Copy your secret key
   (Developers → API keys, starts `sk_...`, use the **test** key first)
   into `STRIPE_SECRET_KEY`.
4. **Webhook**: Developers → Webhooks → Add endpoint. URL:
   `https://<your-site>/api/billing/webhook/stripe`. Events to send:
   `checkout.session.completed` and `customer.subscription.deleted`. Copy
   the **Signing secret** (starts `whsec_...`) into `STRIPE_WEBHOOK_SECRET`.
5. **Why**: `STRIPE_SECRET_KEY` creates real Checkout Sessions server-side
   (`lib/billing/stripe-client.ts`); `STRIPE_WEBHOOK_SECRET` is how the
   webhook route (`lib/billing/stripe.ts`'s `verifyStripeSignature()`)
   proves an incoming request really came from Stripe before it ever
   calls `set_active_subscription()`.
6. **Verify**: With all three Stripe vars set, log in, go to
   `/settings/billing`, click "Upgrade with Stripe" — it should redirect
   to a real Stripe Checkout page (test mode: use card `4242 4242 4242
   4242`, any future expiry/CVC). After paying, you land back on
   `/settings/billing?success=stripe`.
7. **Expected result**: Within a few seconds (webhook delivery), the page
   shows plan "Pro". `select * from public.subscriptions where
   provider = 'stripe' order by created_at desc limit 1;` in the Supabase
   SQL editor shows a real row with `status = 'active'`.

### 4b. Paystack

1. **What**: Create a Paystack account and a subscription Plan for Pro.
2. **Where**: https://dashboard.paystack.com/#/plans → Create Plan.
3. **Exact value**: Copy the **Plan code** (starts `PLN_...`) into
   `PAYSTACK_PLAN_CODE_PRO`. Copy your secret key (Settings → API Keys &
   Webhooks, starts `sk_...`, use the **test** key first) into
   `PAYSTACK_SECRET_KEY`.
4. **Webhook**: Same Settings → API Keys & Webhooks page → Webhook URL:
   `https://<your-site>/api/billing/webhook/paystack`. Paystack signs
   webhooks with this same secret key — there is no separate webhook
   secret to copy.
5. **Why**: Same division of labor as Stripe —
   `lib/billing/paystack-client.ts` initializes a real transaction;
   `lib/billing/paystack.ts`'s `verifyPaystackSignature()` checks the
   `x-paystack-signature` header before any subscription changes.
6. **Verify**: Click "Upgrade with Paystack" at `/settings/billing` — it
   should redirect to a real Paystack payment page (test mode: use card
   `4084 0840 8408 4081`, any future expiry, CVV `408`, OTP `123456`).
7. **Expected result**: Same as Stripe's — plan shows "Pro", a
   `provider = 'paystack'` row appears in `subscriptions`.

### 4c. Flutterwave

1. **What**: Create a Flutterwave account and a Payment Plan for Pro.
2. **Where**: https://dashboard.flutterwave.com/dashboard/payment-plans →
   Create Plan (recurring, monthly, matching your USD amount).
3. **Exact value**: Copy the **Plan ID** into
   `FLUTTERWAVE_PAYMENT_PLAN_ID_PRO`. Copy your secret key (Settings →
   API, starts `FLWSECK_...`, use the **test** key first) into
   `FLUTTERWAVE_SECRET_KEY`.
4. **Webhook**: Settings → Webhooks. URL:
   `https://<your-site>/api/billing/webhook/flutterwave`. Set a **Secret
   Hash** — this is a literal string you invent (not derived from
   anything), *not* an HMAC secret; Flutterwave echoes it back verbatim on
   the `verif-hash` header of every webhook call. Copy the exact same
   string into `FLUTTERWAVE_WEBHOOK_SECRET_HASH`.
5. **Why**: `lib/billing/flutterwave-client.ts` creates a real payment
   link; `lib/billing/flutterwave.ts`'s `verifyFlutterwaveSignature()`
   does a constant-time comparison against `FLUTTERWAVE_WEBHOOK_SECRET_HASH`
   — get this string wrong on either side and every webhook call is
   silently rejected as unauthenticated.
6. **Verify**: Click "Upgrade with Flutterwave" at `/settings/billing` —
   it should redirect to a real Flutterwave payment page (test mode: see
   Flutterwave's test card list in their docs, updated periodically).
7. **Expected result**: Same as the others — plan shows "Pro", a
   `provider = 'flutterwave'` row appears in `subscriptions`.
8. **Known limitation**: unlike Stripe/Paystack, cancelling a
   subscription on Flutterwave's side does not yet auto-downgrade the
   user back to `free` in this build (see ADR 0011) — use an admin manual
   comp (`set_active_subscription(..., 'manual')`) to handle that case
   until a follow-up implements it.

### 4d. Local webhook testing (before you have a public URL)

Each provider's CLI can forward webhook events to `localhost` during
development: Stripe CLI (`stripe listen --forward-to
localhost:3000/api/billing/webhook/stripe`, prints a temporary
`whsec_...` to use locally), or a tunnel tool (ngrok, Cloudflare Tunnel)
pointed at your dev server for Paystack/Flutterwave, whose dashboards
require a real HTTPS URL for webhook registration.

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

## 8. Bot protection on signup (optional)

**Required for**: blocking automated account-creation spam. The signup
form's server action, `signUpAction()`, already contains the real
verification call
(`apps/web/src/lib/turnstile/turnstile-client.ts`'s `verifyTurnstileToken()`)
— until you complete this section, `/signup` simply renders no CAPTCHA
widget at all and every signup proceeds unchecked, exactly as it does
today.

1. **What**: Create a free Cloudflare account and a Turnstile widget (no
   domain ownership/DNS changes to your existing site required — Turnstile
   is independent of whether Cloudflare is your DNS/CDN provider).
2. **Where**: https://dash.cloudflare.com/?to=/:account/turnstile → Add
   site. Widget mode: "Managed" (Cloudflare's recommendation; invisible
   unless it needs to challenge the visitor).
3. **Exact value**: Copy the **Site Key** into
   `NEXT_PUBLIC_TURNSTILE_SITE_KEY` and the **Secret Key** into
   `TURNSTILE_SECRET_KEY`.
4. **Why**: The site key is safe to ship to the browser (it only lets a
   page *request* a challenge) and renders the widget on `/signup`; the
   secret key is what `verifyTurnstileToken()` uses server-side to confirm
   the token the widget produced is real, against Cloudflare's
   `siteverify` endpoint — the same "public key renders, secret key
   verifies" split every payment provider above uses.
5. **Verify**: With both vars set, visit `/signup` — a Turnstile widget
   should appear above the "Create account" button. Submitting without
   completing it (or with a stale/replayed token) is rejected with
   "Verification failed. Please try again."; completing it normally lets
   signup proceed exactly as before.
6. **Expected result**: Automated signup requests that never load/solve
   the widget can no longer create accounts at all.
7. **Required for**: optional — every signup path works identically
   without this configured, just without bot protection.

---

## What's already handled without your action

- Local database testing (`scripts/run-sql-tests.sh`) needs no Supabase
  project — it uses a scratch local Postgres.
- CI (`.github/workflows/ci.yml`) runs lint/typecheck/unit tests/build/DB
  tests/security scan/e2e tests entirely with placeholder values where a
  real Supabase project isn't configured — you do not need to set up
  anything for CI to be useful from day one.
