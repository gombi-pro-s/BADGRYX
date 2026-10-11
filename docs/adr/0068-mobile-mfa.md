# ADR 0068: Mobile MFA — enrollment screen and login step-up

## Status

Accepted.

## Context

ADR 0066 named Security (MFA) as the last open piece of mobile's
Profile/Security/Privacy trio. (Correction while writing this phase:
ADR 0066 and ADR 0067 both cited "ADR 0097" for the original MFA
design -- there is no such ADR; `#97` was a `TaskCreate` task number
("Build login MFA step-up flow"), not an ADR. The real design doc is
ADR 0015, and both files have been fixed to cite it.)

ADR 0015 built two things for web, deliberately separated because
"enrolling a factor" and "actually requiring it" are different
problems: an enrollment screen (`/settings/security`, plain
`supabase.auth.mfa.*` calls, no new schema -- GoTrue owns factor state
entirely) and three enforcement points, all funneling through
`requireUser()` as the one real check every protected Server
Component/Action/Route Handler already calls.

Mobile has no equivalent of `requireUser()` -- no middleware layer, no
server-rendered pages. Its actual single chokepoint is `AuthGate`
(`lib/auth/auth_gate.dart`): every screen this app shows after sign-in
already passes through it, the same way `LoginScreen` already relies
on its `StreamBuilder` to swap to `HomeShell` with no explicit
navigation. That makes `AuthGate` the mobile-architecture equivalent of
`requireUser()` -- not a new parallel mechanism, the existing one
funnel point every protected screen already goes through.

One thing is true on both clients and worth stating plainly rather than
implying otherwise: this step-up check is a UX-level gate, not an
RLS-level one. Postgres RLS has no concept of AAL by default, and
neither this app's web nor mobile policies added one. A stolen aal1
session token could still call any Postgrest/RPC endpoint RLS already
permits at aal1 on either client -- that's equally true of
`requireUser()`'s own redirect, which blocks web's *page-rendering*
path, not a raw Postgrest call against the same project. RLS remains
the one real boundary for data access on both clients, the running
theme of every phase in this app; MFA step-up is a login-flow
protection on top of it, not a replacement for it.

## Decision

- `lib/auth/validation.dart`: `isValidTotpCode(String code)`, a direct
  port of the `/^\d{6}$/.test(code)` check `settings/security/
  actions.ts` and `(auth)/actions.ts` both use.
- `lib/auth/mfa.dart` (new): `needsMfaStepUp(AuthMFAGetAuthenticator
  AssuranceLevelResponse aal)`, a direct port of `signInAction()`/
  `requireUser()`'s own `nextLevel === "aal2" && currentLevel !==
  nextLevel` check. `getAuthenticatorAssuranceLevel()` is synchronous
  in the Dart SDK (confirmed against the real `gotrue` package source),
  unlike the JS SDK's async version -- no `FutureBuilder` needed.
- `lib/auth/auth_gate.dart`: now checks `needsMfaStepUp()` whenever a
  session exists, showing a new `VerifyMfaScreen` instead of
  `HomeShell` when true. `challengeAndVerify()` fires
  `AuthChangeEvent.mfaChallengeVerified` on the exact stream `AuthGate`
  already listens to (confirmed against the real `gotrue` source), so
  completing the challenge makes `AuthGate` rebuild and swap to
  `HomeShell` on its own.
- `lib/auth/verify_mfa_screen.dart` (new): a 6-digit code field,
  verified against the session's first verified TOTP factor via
  `challengeAndVerify()`. Adds one thing web's `/login/verify-mfa`
  doesn't have: a "Log out instead" link. A stuck browser tab still has
  an address bar to navigate away with; a mobile screen with no session
  and no back-stack has no equivalent, so a user without their
  authenticator device (lost phone, reinstalled app) would otherwise
  have no way out at all. Signing out changes nothing about the
  security model -- it's the same action the existing AppBar logout
  button already performs -- so this is a deliberate, mobile-specific
  addition, not scope creep.
- `lib/settings/security_screen.dart` (new): lists verified TOTP
  factors with a two-step "Remove" confirm (mirroring
  `RemoveFactorButton`), and an "Add authenticator app" flow that
  cleans up any previously abandoned unverified factor first (mirroring
  `enrollTotpFactorAction`), then calls `enroll(factorType:
  FactorType.totp)`. Shows the TOTP secret as **plain-text manual-entry
  only, never the QR image**: `enroll()`'s `qr_code` is an SVG data URI
  (confirmed against the real `gotrue` source), and Flutter's `Image`
  widget can't render SVG without a new dependency. The plain-text
  `secret` is an officially documented fallback for exactly this case
  ("in case they are unable to scan the QR code"), not an improvised
  workaround -- web's own form already shows it alongside the QR image
  for the same reason. Logs the same three audit events
  (`mfa.enrollment_started`/`_completed`, `mfa.factor_removed`) via the
  same `log_audit_event()` RPC admin screens already call directly from
  mobile -- it's `GRANT EXECUTE ... TO authenticated` (confirmed against
  the real migration) and stamps `actor_id = auth.uid()` server-side,
  so a plain learner calling it for their own factor is exactly as safe
  as a staff member calling it for a publish toggle.
- `lib/home/more_screen.dart`: a new "Security" entry, next to
  "Profile"/"Language"/"Privacy & data" -- mobile now has all four
  pieces a general Settings hub would hold, though it's still four
  standalone "More" entries rather than one hub screen; folding them
  under a shared `/settings`-style landing page remains a possible,
  separate, cosmetic follow-up, not a functional gap.

## Why

Collapsing web's three enforcement points (middleware, `requireUser()`,
`signInAction()`) into mobile's one `AuthGate` check isn't a shortcut --
it's what mobile's architecture actually has. Mobile never had a
middleware layer or per-page server check to begin with (ADR 0049 made
the same observation for admin-role gating), so there's no second real
checkpoint to mirror; `AuthGate` already was, and remains, the one
place every post-sign-in screen funnels through.

## Consequences

- +10 `flutter test`s (`mfa_test.dart`: 4 cases; `validation_test.dart`:
  6 new `isValidTotpCode` cases) -- 255 total (was 245). `flutter
  analyze` clean, `flutter build web` succeeds both configs. No new
  dependency.
- Closes the last named item in the Profile/Security/Privacy trio ADR
  0066 opened. Fixes the "ADR 0097" citation error in ADR 0066/0067.
- No SQL migration and no SQL regression test, for the same reason
  ADR 0015 had none on web: MFA state lives entirely in GoTrue's own
  `auth.mfa_factors`, a table this schema doesn't own or touch.
- Like ADR 0015 itself, this cannot be click-tested end-to-end in this
  sandbox -- no real Supabase project to authenticate against. Verified
  by `flutter analyze`, `flutter test`, and a clean `flutter build web`
  (both configs) instead.
