# iCorePen Mobile

A Flutter client for the same Supabase project `apps/web` uses -- Auth and
Postgres (RLS-scoped) access via `supabase_flutter`, no separate mobile
backend. See [ADR 0026](../../docs/adr/0026-flutter-mobile-foundation.md)
for what's built so far and what's honestly still ahead.

## What's real here today

- Real Supabase Auth: sign up (email/password, same password policy as
  `apps/web`), log in, log out, session persisted across app restarts by
  `supabase_flutter`.
- Three real authenticated tabs (bottom navigation):
  - **Home**: `/dashboard`'s equivalent -- your real display name, your
    real active plan (or "Free"), and up to 5 real active announcements.
  - **Skills**: `/skills`'s equivalent -- your own skill list with its
    real, per-user state, read live from `skills` and `user_skill_states`
    under the exact same RLS this repo's SQL tests already prove.
  - **CTF**: `/ctf`'s equivalent -- published challenges
    (`ctf_challenges_public`, flag hash never exposed) and a real flag
    submit calling the same `submit_ctf_flag()` RPC the web app calls --
    correct/incorrect is never decided client-side.
- This is still a first vertical slice, not the whole web app. Labs
  (including the terminal/Cyber Range simulator), investigations,
  capstones, exams, Mentor, the scanner, billing, and every admin flow do
  not have a mobile screen yet.

## Configuration

No `.env` file is bundled into the app. Supabase config is supplied at
build/run time via `--dart-define` (see `lib/config/env.dart`):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

The exact same project/keys as `apps/web/.env.local` (see the root
`MANUAL_SETUP.md` §2). Running without these set shows a real
"Supabase is not configured" screen rather than crashing or silently
using placeholder data -- this app has no functionality at all without
a real backend, unlike an optional integration (Turnstile, a billing
provider) that can degrade gracefully.

## Verifying this app in a sandbox with no Android/iOS toolchain

This was built and verified in an environment with the Flutter SDK but
**no Android SDK, no Xcode, no Chrome, and no GTK dev libraries** --
the same kind of honest limitation `apps/web`'s `MANUAL_SETUP.md` and
`RELEASE_CHECKLIST.md` document repeatedly for that app (no `supabase`
CLI, no Docker daemon, no real Supabase project). What that means here:

- `flutter analyze` and `flutter test` need no device/platform toolchain
  and run clean.
- `flutter build web --dart-define=...` is the one real production build
  verified in that environment (it needs only the Dart/web SDK, already
  bundled with Flutter).
- `flutter build apk`/`flutter build ipa` have **not** been run here --
  they need the Android SDK / Xcode respectively, neither of which exist
  in that sandbox. CI (`.github/workflows/ci.yml`'s `mobile` job) runs the
  same analyze/test/web-build sequence; a real device/emulator
  click-through and a real Android/iOS release build still need to be
  done from a machine with those toolchains installed, exactly the same
  "needs a provisioned environment this sandbox doesn't have" honesty as
  the web app's own remaining manual-verification items.

## Running the tests

```bash
cd mobile/app
flutter pub get
flutter analyze
flutter test
```
