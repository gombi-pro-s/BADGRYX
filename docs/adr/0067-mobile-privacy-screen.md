# ADR 0067: Mobile Privacy screen (data export + account deletion)

## Status

Accepted.

## Context

ADR 0066 named Security (MFA) and Privacy (export/delete) as the two
remaining pieces of mobile's missing Profile/Security/Privacy settings
surface. Privacy is the one worth closing next: unlike MFA (which needs
new login-time AAL handling on top of enrollment UI, roughly doubling
ADR 0097's own scope), Privacy is two self-contained operations, and
closing it finally exercises the Bearer-token Route Handler pattern
(ADR 0033) for the one thing in this app that genuinely cannot be done
with Postgrest alone: account deletion needs the GoTrue Admin API
(`service_role`), which only a server can hold.

`GET /api/account/export` already existed but used `requireUser()`
(cookie-only) -- fine for the web form's own `<a href>` download link,
unreachable from a Bearer-only mobile caller. There was no
`/api/account/delete` Route Handler at all; `deleteMyAccountAction`
(the web Server Action) called `createAdminClient().auth.admin.
deleteUser()` directly, inline, with no Route Handler counterpart.

Following ADR 0058's own precedent (`importPathBundle()` shared between
`importPathBundleAction` and `/api/admin/paths/import`): the actual
deletion logic is extracted into one shared function, called by both
the existing Server Action and the new Route Handler, rather than
hand-ported a second time in Dart where it could drift from the
original.

## Decision

- `lib/account/confirm-deletion.ts` (new, no `"server-only"` --
  mirrors `announcement-translation.ts`'s own reasoning: a pure check
  usable from either server or client code shouldn't need a
  server-only import): `confirmsAccountDeletion(confirmation, email)`.
- `lib/account/delete-account.ts` (new, `"server-only"`):
  `deleteAccount(supabase, user, confirmation)` -- the audit-log-then-
  `admin.auth.admin.deleteUser()` sequence `deleteMyAccountAction` used
  to run inline, now shared.
- `settings/privacy/actions.ts`'s `deleteMyAccountAction` now just
  calls `deleteAccount()`, then signs out and redirects -- unchanged
  behavior, less logic owned in two places.
- `app/api/account/delete/route.ts` (new): `POST`, Bearer-authed via
  `requireApiUser()`, parses `{ confirmation }`, calls the same
  `deleteAccount()`. Can't `redirect()` the way the Server Action does
  -- that's a Next.js Server Action/page concept with no Route Handler
  equivalent -- so it returns `{ ok: true }` and leaves navigation to
  the caller.
- `app/api/account/export/route.ts`: `requireUser()` → `requireApiUser
  (request)`. `apps/web`'s own `<a href="/api/account/export" download>`
  link keeps working unchanged (no Bearer header sent, falls through to
  the cookie path); a mobile caller can now reach it with a Bearer
  token.
- Mobile `lib/settings/privacy.dart` (new): `confirmsAccountDeletion()`,
  a direct Dart port, checked client-side before any network call --
  the real boundary is still server-side, same belt-and-suspenders
  pattern every other validated form in this app uses.
- Mobile `lib/settings/privacy_screen.dart` (new): a "Privacy & data"
  entry on "More". Export GETs `/api/account/export` and shows the
  bundle in a copy-to-clipboard dialog, the exact pattern the admin
  Learning Paths screen's path export already established -- no new
  file-storage dependency. Delete starts collapsed (a plain danger
  button), expands into a "type your email to confirm" field mirroring
  `delete-account-form.tsx`'s own flow, and on success calls
  `Supabase.instance.client.auth.signOut()` locally (the account is
  already gone server-side) so `AuthGate` shows the login screen again
  -- the same end state web's `redirect("/login?deleted=1")` reaches.
  Degrades to a plain "not configured on this build" message without
  `API_BASE_URL`, same as Billing/Mentor/Scanner.

## Consequences

- Web: +6 `vitest` tests (`confirm-deletion.test.ts`) -- 329 total (was
  323). `tsc --noEmit`, ESLint, and `npm run build` all clean. No
  behavior change for existing browser callers of either route.
- Mobile: +6 `flutter test`s (`privacy_test.dart`) -- 245 total (was
  239). `flutter analyze` clean, `flutter build web` succeeds both
  configs. No new dependency.
- Closes the Privacy half of the gap ADR 0066 named. Security (MFA
  enrollment + login step-up) remains the one open item from that ADR's
  Context.
