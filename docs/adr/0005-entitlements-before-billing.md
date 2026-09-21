# ADR 0005: Build the entitlement engine now; defer live payment provider wiring

## Status

Accepted (per explicit product decision at project kickoff).

## Context

Section 28 of the spec requires entitlements to be verified server-side and
never trusted from client state. It does not require a specific payment
provider on day one. Live billing integration (Stripe/Paystack/Flutterwave)
requires an external account and API keys that only the human owner can
create (see `MANUAL_SETUP.md`) — it cannot be "finished" inside this build
environment regardless of engineering effort.

## Decision

Build the full entitlement data model and enforcement now, provider-agnostic:

- `plans` (catalog) and `plan_entitlements` (flexible key→value limits per
  plan) describe what a plan grants.
- `subscriptions` records who has which plan and its status, with a
  `provider` column (`'stripe' | 'paystack' | 'flutterwave' | 'manual' |
  NULL`) so a webhook handler for any provider only needs to call
  `set_active_subscription()` — no product code changes when a provider is
  connected later.
- `billing_webhook_events` provides replay protection (a hard
  `UNIQUE (provider, provider_event_id)` constraint) for whichever
  webhook handler is wired in later.
- `get_entitlement()` is the one function product code should call to check
  a limit; it resolves the subject's current active subscription's plan, or
  falls back to the `free` plan.
- Every new user is auto-enrolled on the `free` plan via a trigger on
  `auth.users`, with real, currently-enforced limits (not placeholder
  values) seeded in the same migration.
- `provider = 'manual'` subscriptions (admin comps) use the exact same
  table and function as a future real provider integration would — there is
  no separate "fake billing" code path to later delete.

## Why

This lets every other part of the product (labs, cyber range access, AI
Mentor request quotas, team management) be built against a real,
enforced entitlement check from day one, instead of skipping entitlement
checks now and retrofitting them once a payment provider exists (a common
source of "wait, was this ever actually gated?" bugs).

## Consequences

- Connecting a real payment provider later is additive: implement its
  webhook handler (verify signature, then call `set_active_subscription()`
  and log to `billing_webhook_events`), and set the real price/plan data.
  No RLS policy or entitlement-check code should need to change.
- Until a provider is connected, all plan changes are `provider = 'manual'`
  admin actions. This is documented as a real limitation, not hidden: see
  `RELEASE_CHECKLIST.md`.
- `supabase/tests/004_entitlements.sql` proves a client can never
  self-upgrade, that webhook replay is rejected, and that only one active
  subscription per subject exists at a time.
