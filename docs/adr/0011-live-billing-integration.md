# ADR 0011: Live billing integration -- checkout + webhooks for Stripe, Paystack, and Flutterwave

## Status

Accepted.

## Context

ADR 0005 built the full entitlement/billing data model
(`plans`/`plan_entitlements`/`subscriptions`/`billing_webhook_events`,
`get_entitlement()`/`set_active_subscription()`) deliberately
provider-agnostic and deferred connecting a real payment provider, since
that requires an external account and API keys only the human owner can
create. This build environment still cannot create a real Stripe/Paystack/
Flutterwave account or hold live secret keys -- but every piece of code
that doesn't require one is now real and complete: request-building,
signature verification, checkout initiation, and webhook processing for
all three providers, gated entirely behind environment variables (see
`.env.example`) exactly like `ANTHROPIC_API_KEY` already is.

There was also a real, pre-existing gap this phase closes: only the `free`
plan existed. There was nothing to actually upgrade to.

## Decision

- Seed a real `pro` plan (`20260922000015_seed_pro_plan.sql`) with real,
  better-than-free entitlement values across every gated feature this app
  has (`lab_instances_concurrent`, `ai_mentor_daily_requests`,
  `scanner_daily_scans`, `scanner_daily_enrichments`,
  `cyber_range_access`, `team_management`, `advanced_reports`).
- Support all three providers ADR 0005 named, provider-agnostic dispatch:
  each gets its own checkout-initiation code path and its own webhook
  route (`/api/billing/webhook/{stripe,paystack,flutterwave}`), but all
  three ultimately call the same `set_active_subscription()` RPC ADR 0005
  already built -- no product code outside `lib/billing/` and these three
  routes needed to change.
- **Pure logic separated from server-only I/O**, the same pattern as
  `lib/mentor/prompt.ts` vs `client.ts`: `lib/billing/{stripe,paystack,
  flutterwave}.ts` hold signature verification and request-building as
  pure functions with no `server-only` import, fully unit-tested without
  a real account or network access; `lib/billing/{stripe,paystack,
  flutterwave}-client.ts` hold the actual `fetch()` calls, `server-only`
  guarded.
- **No provider SDKs.** All three integrations are implemented directly
  against each provider's REST API with `fetch` and Node's built-in
  `crypto` module for signature verification, rather than pulling in
  `stripe`/a Paystack/Flutterwave package. This keeps the dependency
  surface at zero new packages and every security-critical line
  (signature verification) auditable in this repository rather than
  trusted to a third party -- consistent with this app's own terminal
  interpreter, scanner rule engine, and answer-hashing all being
  hand-rolled rather than pulled from a library.
- **Idempotent webhook processing.** Every webhook call is logged to
  `billing_webhook_events` first, keyed by `(provider, provider_event_id)`
  -- Stripe's real event `id`; Paystack has no stable top-level event id,
  so `${event}:${reference}` is used instead; Flutterwave's transaction
  `id`. A unique-constraint violation on that insert means "already
  processed this exact event" and returns success immediately without
  reprocessing, so a provider's automatic retry-on-non-2xx behavior can
  never double-activate or double-charge a subscription change.
- **Webhook routes run as `service_role`** (`createAdminClient()`), the
  same as ADR 0005 always intended -- an incoming webhook has no user
  session to authenticate as, and `set_active_subscription()` only accepts
  `is_admin() OR auth.role() = 'service_role'`.
- **`client_reference_id`/`metadata.user_id`/`meta.user_id`** (Stripe/
  Paystack/Flutterwave's respective mechanisms) carry this app's internal
  user id through checkout, set at session-creation time -- the webhook
  never has to guess who paid from an email address alone.
- **`current_period_end` is computed, not fetched.** Stripe's
  `checkout.session.completed` event doesn't include a subscription's
  period end without an extra API call to expand it; rather than add that
  call, `lib/billing/plans.ts`'s `computePeriodEnd()` derives it from the
  plan's billing interval at the moment of activation. Documented as a
  simplification, accurate within the billing cycle it represents.
- **Cancellation is fully wired for Stripe only in this build.**
  `customer.subscription.deleted` downgrades the subject back to `free`
  automatically. Paystack's `subscription.disable` is also handled.
  Flutterwave's cancellation webhook shape varies more by integration
  setup and isn't implemented yet -- documented as a known limitation in
  `RELEASE_CHECKLIST.md`, not silently missing.

## Why

This mirrors ADR 0005's own principle one level deeper: build everything
that doesn't require an external secret, make the one missing piece
(real API keys) a pure configuration gap with a clear, honest UI state
("not configured yet") rather than a half-built feature. Someone with a
real Stripe/Paystack/Flutterwave account can go from zero to accepting
real payments by setting environment variables alone -- no code changes.

## Consequences

- Until real keys are configured, `/settings/billing`'s upgrade buttons
  render as disabled "(not configured)" for each provider, and that
  provider's webhook route returns `503`. This is intentional, tested
  behavior, not an oversight.
- `supabase/tests/004_entitlements.sql` was extended to prove the real
  `pro` plan (not the pre-existing escalation-prevention test fixture,
  which was renamed off the now-real `pro` slug to avoid colliding with
  it) grants real, better-than-free entitlements once
  `set_active_subscription()` activates it.
- Adding a second paid tier later means resolving an incoming price/plan
  identifier to a plan slug in each webhook handler, instead of the
  current hardcoded `PRO_PLAN_SLUG` -- an intentional, documented
  simplification for "exactly one paid plan," not an architectural dead
  end (the `plans` table itself already supports any number of rows).
