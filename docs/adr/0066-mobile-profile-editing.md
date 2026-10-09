# ADR 0066: Mobile Profile editing screen

## Status

Accepted.

## Context

ADR 0065 named, in passing, that mobile has no Profile/Security/
Privacy settings screen at all -- "Language" was deliberately added
standalone to "More" rather than folded into a settings hub that
doesn't otherwise exist. Of the three, Profile is the one worth closing
first: `/settings`'s own Profile form (`profile-form.tsx` +
`actions.ts`) is a single, plain Postgrest update (`profiles_update_own`
RLS is the real boundary) with no RPC, no admin client, and no Route
Handler -- directly portable with nothing new on the backend.

Security (MFA enrollment) and Privacy (data export, account deletion)
remain open. MFA enrollment turns out not to need a new dependency
either -- Supabase Auth's own `enroll()` call returns a plain-text TOTP
secret alongside the QR code, and web's own form already shows that
secret as a manual-entry fallback, so mobile could skip rendering a QR
image entirely -- but it's a materially larger phase: mobile's
`lib/auth/` has zero AAL/MFA handling today, so it would need both an
enrollment screen and a login-time step-up check, roughly doubling
ADR 0097's own scope. Account deletion is the one piece in all three
that cannot be done with Postgrest alone: `deleteMyAccountAction` calls
`createAdminClient()` (`service_role`), reachable today only as a
cookie-session Server Action, with no existing Route Handler --
closing it would mean a genuinely new Bearer-authed endpoint, the
`requireApiUser()` pattern ADR 0033 established. Both are named here as
the remaining items, not bundled into this phase.

## Decision

- `lib/settings/profile.dart` (new): `validateProfileUpdate()`, a
  direct port of `settings/actions.ts`'s `profileSchema` (a zod
  object), checked in the same field order (display_name, username,
  bio, timezone) zod's `issues[0]` reports first. The three plain
  length-exceeded messages ("Too big: expected string to have <=N
  characters") are zod v4's own default wording, verified by running
  the real schema through `node`, not an invented string -- in
  practice they're defensive only, since the matching `TextField`'s
  own `maxLength` already stops a user from typing past the limit.
  `buildProfileUpdateRow()` mirrors `updateProfileAction`'s row shape:
  an empty `username`/`bio` is stored as `null`, never `''`.
- `lib/settings/profile_screen.dart` (new): loads the four fields from
  `profiles`, lets the user edit them, validates with
  `validateProfileUpdate()`, then calls a plain `.update()` the same
  shape `buildProfileUpdateRow()` returns. A caught `PostgrestException`
  with code `23505` (the unique `username` constraint) shows "That
  username is already taken.", the exact message
  `updateProfileAction` returns for the same error code.
- `lib/home/more_screen.dart`: a new "Profile" entry, placed next to
  "Language" since both are personal-settings items -- still no
  general "Settings" hub, since Security and Privacy remain unbuilt.

## Consequences

- +13 `flutter test`s (`profile_test.dart`) -- 239 total (was 226).
  `flutter analyze` clean, `flutter build web` succeeds both configs.
  No new dependency and no new backend endpoint.
- Narrows, but doesn't close, the gap ADR 0065 named: mobile still has
  no Security (MFA) or Privacy (export/delete) screen. Those remain
  named, separate, larger gaps -- Security needs new login-time AAL
  handling on top of enrollment UI, and Privacy's account-deletion half
  needs a new Bearer-authed Route Handler, neither of which this phase
  bundles in.
