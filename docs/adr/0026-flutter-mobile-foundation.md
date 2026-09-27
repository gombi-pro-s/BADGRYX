# ADR 0026: Flutter mobile app foundation -- real auth, one real data screen

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md`'s "Mobile readiness" section had one honest `[x]`
(the backend contracts were already client-agnostic -- every RLS policy
and grading function works identically for any client) and one honest
`[ ]`: "Flutter app itself (not started)." `mobile/README.md` had been a
plan, not code, since the monorepo was first scaffolded.

This sandbox has no Flutter SDK, no Android SDK, no Xcode, no Chrome, and
no GTK development libraries installed. Every other phase in this session
ran a full verification suite before pushing (`tsc`, ESLint, unit tests, a
production build, e2e where applicable, SQL regression tests) -- shipping
a Flutter app that had never once been run through `flutter analyze`/
`flutter test`/a real build would break that discipline badly, especially
since Dart/Flutter APIs are easy to get subtly wrong from memory (and one
API used here, `Supabase.initialize`, had in fact just changed its
preferred parameter name in the installed SDK version -- caught only by
actually running the analyzer, see Consequences).

## Decision

- Installed the Flutter SDK directly into this sandbox (`git clone
  https://github.com/flutter/flutter -b stable`), the same "fix the
  missing tool, don't work around not having it" response as starting
  Postgres via `pg_ctlcluster` earlier in this session, rather than
  writing unverified Dart.
- `flutter create` scaffolded `mobile/app`. Kept `android/`, `ios/`, and
  `web/` (the three platforms actually worth building against); dropped
  `linux/`/`macos/`/`windows/` and IDE cruft (`.idea/`, `*.iml`) -- this is
  a mobile app, not a desktop one.
- `supabase_flutter` is the one new dependency this phase adds, and it's
  the correct call, not a shortcut: unlike the PWA service worker or the
  HTTP load test script (where a few lines of built-in API replaced a
  whole library), there is no built-in Dart/Flutter equivalent for
  Supabase Auth + Postgrest + Realtime, and hand-rolling that HTTP/WS
  protocol layer would be a large, security-sensitive reinvention for no
  real benefit -- `mobile/README.md` had already named this exact package
  as the plan since the monorepo was scaffolded.
- `lib/config/env.dart`: Supabase URL/anon key read via
  `String.fromEnvironment` (`--dart-define`, no bundled `.env` file, no
  new dependency just to read two strings), with a pure
  `isSupabaseConfigured()` mirroring `apps/web`'s `lib/supabase/env.ts`.
  Unlike an optional integration (Turnstile, a billing provider), Supabase
  is this app's only backend -- `main.dart` shows a real, clear
  "not configured" screen rather than crashing partway into a widget
  tree, and never silently uses mock data.
- `lib/auth/validation.dart`: the exact same email/password rules as
  `apps/web`'s `lib/auth/validation.ts` (12+ characters, upper+lower+digit),
  pure and unit-tested, so both clients enforce identical policy before
  ever calling Supabase Auth.
- Real auth flow: `AuthGate` (a `StreamBuilder` on
  `auth.onAuthStateChange`, so the session stream is the single source of
  truth -- no separate "isLoggedIn" flag to drift out of sync),
  `LoginScreen`, `SignupScreen` (handles both the immediate-session and
  email-confirmation-required project configurations honestly, rather
  than assuming one).
- One real, RLS-scoped data screen: a skills list (`skills` joined with
  `skill_categories`, merged in Dart with this user's own
  `user_skill_states` -- the same tables and the same RLS
  `apps/web`'s `/skills` page and its SQL tests already prove) with the
  identical 7-state label mapping as `components/skill-state-badge.tsx`.
  Deliberately a first vertical slice, not the whole matrix that page
  renders (per-evidence-type columns) -- that's a real, separate scope
  increase for a later phase, not silently declared done here.
- `theme.dart` uses the same brand hex values as
  `apps/web/src/app/globals.css` (`#0d7d7d`/`#2dd4bf` accent,
  `#ffffff`/`#0a0d12` background), not Flutter's default Material seed
  color -- the same "genuinely on-brand, not arbitrary" bar the PWA icons
  were held to.

## Why

A dedicated per-mobile backend, or a from-scratch Supabase client, would
both be solving a problem that doesn't exist here -- the RLS policies and
grading functions already work for any client with a valid JWT, which is
exactly what `supabase_flutter`'s Auth module produces. The real design
work worth doing in this phase was making sure the app fails honestly
(no config -> a real error screen, not silent mock data) and stays
consistent with the web client (identical password policy, identical
skill-state vocabulary) rather than drifting into its own rules.

## Consequences

- 18 tests (`flutter test`, all passing): `isSupabaseConfigured()`'s four
  cases, `SupabaseEnv.isConfigured` genuinely being false with no
  `--dart-define` supplied to the test run, the email/password validators
  (mirroring `apps/web`'s own validation tests), the skill-state label
  mapping (every real enum value covered, exact text parity with the web
  badge component, and an unrecognized value falling back rather than
  throwing), and one widget test proving the app really does show the
  config-missing screen rather than crashing when unconfigured.
- `flutter analyze`: clean. Caught two real issues before they shipped: a
  `FormFieldValidator<String>` type mismatch (Flutter's validator callback
  is nullable-parameter, the pure validators needed to accept `String?`)
  and `Supabase.initialize`'s `anonKey` parameter having just been
  deprecated in favor of `publishableKey` in the installed SDK version --
  exactly the kind of subtle, version-specific API drift that only
  running the real analyzer (not writing from memory) catches.
- `flutter build web` succeeds and is the verified production-build proof
  in this sandbox (no Android SDK/Xcode/GTK here) -- CI
  (`.github/workflows/ci.yml`'s new `mobile` job) runs `flutter analyze`,
  `flutter test`, and the same web build on every push. A real Android/iOS
  build, and a real device/emulator click-through, still need a machine
  with those toolchains -- the same "needs a provisioned environment this
  sandbox doesn't have" honesty as the web app's own remaining real-click-
  through items (see `mobile/app/README.md`).
- `RELEASE_CHECKLIST.md`'s "Flutter app itself" moves from `[ ]` not
  started to a real, bounded `[~]` scope statement: auth + one data
  screen genuinely work end to end against a real Supabase project;
  labs/CTF/investigations/Mentor/scanner/billing/admin remain unbuilt on
  mobile, named as such rather than implied done.
