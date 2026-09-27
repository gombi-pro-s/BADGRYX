# ADR 0037: Billing screen in the Flutter mobile app

## Status

Accepted.

## Context

Unlike AI Mentor (ADR 0034) and the Security Scanner's scan submission
(ADR 0036), reading a user's own billing status needs no Route Handler at
all -- `subscriptions`, `plans`, and `plan_entitlements` are plain,
RLS-scoped Postgrest queries, identical in shape to every other read-only
mobile screen (Skills, CTF, Capstones). The dashboard tab already showed
a one-line plan name (`planNameFromSubscriptionRow()`, ADR 0026); this
phase is the fuller `/settings/billing` equivalent: status, description,
and entitlements.

Checkout itself is different. `apps/web`'s Stripe/Paystack/Flutterwave
checkout each redirect to that provider's own hosted, PCI-compliant page
-- there is no reasonable way to "port" that to Flutter without either a
provider-specific mobile SDK (a real, non-trivial integration per
provider) or a WebView wrapping the same hosted page (extra complexity
and a worse experience than just using the browser). Building any of that
for a first billing slice would be a much larger, separate decision than
"show the user their real plan."

## Decision

- `lib/billing/billing.dart`: `BillingSubscription`/`BillingPlan`/
  `PlanEntitlement` row parsers, and two pure helpers mirroring
  `settings/billing/page.tsx` exactly: `isProPlan(slug)` (`slug == 'pro'`)
  and `formatEntitlementKey(key)` (`key.replaceAll('_', ' ')`).
- `lib/billing/billing_screen.dart`: the user's real plan name, status, a
  "Pro" chip when applicable, plan description, and every entitlement
  (server-enforced by `get_entitlement()`, never invented client-side) --
  all read-only, no new dependency, no Route Handler call.
- **Checkout/upgrade/cancel deliberately not built.** The screen shows a
  plain-text note that managing or upgrading a plan happens on the web
  app's `/settings/billing` page. No `url_launcher` (or any other new
  dependency) was added to make that note a tappable link -- consistent
  with this project's standing "no new dependency without a concrete need
  this phase actually has" discipline (the same reasoning that kept load
  testing and the PWA service worker hand-rolled).
- Wired into `MoreScreen`'s menu, alongside AI Mentor and Security
  Scanner.

## Why

Read-only billing status is real, immediate value with zero new risk
surface (no payment data ever touches the mobile app, no new external
dependency, no service_role anywhere). A checkout/cancel flow is a
materially different, larger decision -- which payment SDK(s) to embed,
how a webhook-driven status update reaches a mobile client, whether a
WebView checkout is acceptable UX -- that deserves its own explicit
choice rather than being smuggled into this phase to make it feel
"complete." Naming it as a boundary is the honest choice.

## Consequences

- +9 unit tests (`billing_test.dart`: subscription/plan/entitlement row
  parsing including a null `current_period_end`, `isProPlan()`'s three
  cases, `formatEntitlementKey()`'s two cases) -- 86 `flutter test`s
  total (was 77).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- No new dependency.
- Checkout, upgrade, cancellation, and any webhook-driven live update on
  mobile remain explicitly out of scope until a real decision is made
  about how to handle a payment provider's hosted checkout from a native
  app.
