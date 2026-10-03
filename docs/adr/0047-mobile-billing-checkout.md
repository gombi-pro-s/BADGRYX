# ADR 0047: Real checkout on the mobile Billing screen

## Status

Accepted.

## Context

ADR 0037 named checkout/upgrade/cancel as a deliberate scope boundary for
the mobile Billing screen: "a payment provider's hosted checkout page
isn't something to reimplement in-app." That reasoning still holds for
*embedding* a provider's checkout page -- card details should never
touch this app -- but reading `settings/billing/actions.ts` showed
starting checkout itself needs nothing provider-specific client-side: each
of the three `createXCheckoutAction()`s calls a plain
`create{Stripe,Paystack,Flutterwave}{CheckoutSession,Transaction,Payment}()`
helper (already provider-agnostic `{url: string}` returns) and then
`redirect(url)` -- a browser-only step. Swap that one `redirect()` for a
JSON response and the exact same server-side call, with the exact same
secret keys that must never leave the server, works for any caller.

Canceling or otherwise managing an existing subscription is a separate,
still-deferred piece: it is a smaller, less urgent action (nothing time-
sensitive blocks on it, unlike getting a new user onto Pro) and stays on
the web app for this phase, named below rather than silently missing.

## Decision

- `apps/web/src/app/api/billing/checkout/route.ts` (new): Bearer-authed
  via `requireApiUser(request)` (ADR 0033's pattern), takes
  `{ provider: "stripe" | "paystack" | "flutterwave" }`, runs the same
  `isXConfigured()` check and provider call as the matching web action,
  and returns `{ url }` JSON (or `{ error }` with 400/502) instead of
  redirecting. `successUrl`/`cancelUrl` always point at the web app's
  `/settings/billing` (that's where the subscription webhook's effect
  becomes visible regardless of which client started checkout).
- `e2e/smoke.spec.ts`'s `mobile API auth` block gained a sixth 401-proof
  test for this route -- 33 e2e tests total.
- `mobile/app/lib/billing/billing.dart` gained `checkoutProviderLabel`,
  the three provider ids mapped to their display labels (mirrors
  `settings/billing/page.tsx`'s three `UpgradeButton` labels).
- `mobile/app/lib/billing/billing_screen.dart`: when not already Pro and
  `AppEnv.isApiConfigured`, one `FilledButton` per provider POSTs to the
  new route with the session's Bearer token, then shows the returned
  checkout URL in a copy-link dialog -- the same pattern as the
  Organizations screen's invite-link flow, deliberately not a WebView,
  since this app still never touches card details either way.

## Why

Reusing the web action's exact provider calls and configured-check means
mobile checkout can never drift from web checkout on what "configured"
means or what parameters a provider gets -- there is exactly one place
that decides, same as every other Bearer-authed route in this app.

## Consequences

- +1 `flutter test` (`checkoutProviderLabel` covers exactly the three
  known providers with real labels) -- 121 `flutter test`s total (was
  120); 33 e2e tests total (was 32); web unit tests, `tsc --noEmit`,
  ESLint, and a production build all stay clean.
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL`.
- Narrows ADR 0037's Billing gap to just canceling/managing an existing
  subscription, named above rather than silently missing.
