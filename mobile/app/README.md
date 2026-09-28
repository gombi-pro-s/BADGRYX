# iCorePen Mobile

A Flutter client for the same Supabase project `apps/web` uses -- Auth and
Postgres (RLS-scoped) access via `supabase_flutter`, no separate mobile
backend. See [ADR 0026](../../docs/adr/0026-flutter-mobile-foundation.md)
for what's built so far and what's honestly still ahead.

## What's real here today

- Real Supabase Auth: sign up (email/password, same password policy as
  `apps/web`), log in, log out, session persisted across app restarts by
  `supabase_flutter`.
- Five bottom-nav tabs, plus three more screens reachable behind "More"
  (see ADR 0032 for why this replaced a flat, growing tab bar):
  - **Home**: `/dashboard`'s equivalent -- your real display name, your
    real active plan (or "Free"), and up to 5 real active announcements.
  - **Labs**: `/labs`'s equivalent -- published labs, start guided/
    unguided, unlock hints, a real flag submit through the same
    `submit_lab_flag()` RPC the web app calls, and, for terminal-backed
    labs, a real interactive terminal (`Open terminal` once a lab
    instance exists) -- the exact same server-side interpreter and
    multi-host ssh/exit pivoting `apps/web` uses, authenticated with a
    Bearer token (see ADR 0039/0040). Command-history recall (up/down
    arrow) is web-only -- a touch keyboard has no arrow keys to bind it
    to -- named as a real, deliberate gap rather than silently missing.
  - **Skills**: `/skills`'s equivalent -- your own skill list with its
    real, per-user state, read live from `skills` and `user_skill_states`
    under the exact same RLS this repo's SQL tests already prove.
  - **CTF**: `/ctf`'s equivalent -- published challenges
    (`ctf_challenges_public`, flag hash never exposed) and a real flag
    submit calling the same `submit_ctf_flag()` RPC the web app calls --
    correct/incorrect is never decided client-side.
  - **More**:
    - **Investigate**: `/investigate`'s equivalent -- real case evidence
      artifacts, a mixed multiple-choice/exact-text answer form graded
      server-side via `submit_investigation_answers()`, and a private,
      debounced-autosave notes scratchpad (not even staff can read it).
    - **Exams**: `/exams`'s equivalent -- a real countdown timer, single/
      multi-choice answers, grading exclusively through
      `submit_quiz_attempt()`. Same honestly-documented limitation as the
      web app: the timer is client-side only (a refresh restarts it).
    - **Capstones**: `/capstones`'s equivalent -- skill/lab tag chips,
      submission history with reviewer notes, and a plain report
      submission (a direct `capstone_submissions` insert, no RPC).
    - **AI Mentor**: `/mentor`'s equivalent, general-chat modes only
      (Explain/Hint/Teach/Analyze a failure -- no lab/lesson/finding deep
      links from mobile yet). Streams the exact same NDJSON
      `/api/mentor/chat` Route Handler `apps/web` calls, authenticated with
      an `Authorization: Bearer <session.accessToken>` header instead of a
      browser cookie (see ADR 0033); text streams into the reply bubble
      token-by-token, and the day's request quota is shown once a reply
      finishes. Needs a second, **optional** build-time config value --
      see Configuration below -- and degrades to a plain "not configured
      on this build" message if it's absent, rather than blocking the rest
      of the app.
    - **Security Scanner**: `/scanner`'s equivalent -- past scans plus a
      combined posture summary, a "New scan" screen that pastes code and
      submits it through the same `Authorization: Bearer` path as the
      Mentor to `/api/scanner/scan` (see ADR 0033/0035), and a read-only
      scan-detail screen showing each finding (severity-coded,
      most-severe-first) with its evidence/explanation/impact/remediation.
      Pasted-snippet scans only (no file upload yet); no "Enrich with AI"
      or manual status-transition actions yet either -- both need this
      screen's read-only foundation first, and are named as gaps rather
      than silently missing. See ADR 0036.
    - **Billing**: `/settings/billing`'s read side -- your real plan,
      subscription status, and every entitlement, straight from
      `subscriptions`/`plans`/`plan_entitlements` under the same RLS as
      the web app, no Route Handler needed. Checkout/upgrade/cancel are
      deliberately not built: a payment provider's hosted checkout page
      isn't something to reimplement in-app for a first slice, so the
      screen just says to manage your plan from the web app. See
      ADR 0037.
    - **Organizations**: `/orgs` and `/orgs/[orgId]`'s equivalent -- your
      real memberships, a "Create organization" flow, the member roster
      (admins can change roles or remove members via the real
      `update_organization_member_role()`/`remove_organization_member()`
      RPCs; anyone can leave), and, for admins, a real invite-link flow
      (`create_organization_invitation()`) with revoke. Plain RLS-scoped
      Postgrest/RPC, no Route Handler needed. The instructor dashboard
      (real per-member progress) and org-scoped announcement authoring
      stay web-only -- both are substantial features of their own, not
      silently missing. See ADR 0041.
- This is still a first vertical slice, not the whole web app. Every
  other admin/instructor flow does not have a mobile screen yet. Future
  pillars like these belong behind "More" too, not as new flat tabs.

## Configuration

No `.env` file is bundled into the app. Supabase config is supplied at
build/run time via `--dart-define` (see `lib/config/env.dart`):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key> \
  --dart-define=API_BASE_URL=https://<your-apps-web-deployment>
```

The exact same project/keys as `apps/web/.env.local` (see the root
`MANUAL_SETUP.md` §2). Running without `SUPABASE_URL`/`SUPABASE_ANON_KEY`
set shows a real "Supabase is not configured" screen rather than crashing
or silently using placeholder data -- this app has no functionality at
all without a real backend.

`API_BASE_URL` (the origin `apps/web` is deployed at) is different:
**it's optional**. It's only needed for the three screens that call that
deployment's Route Handlers directly rather than talking to Supabase --
AI Mentor (`/api/mentor/chat`, see ADR 0033/0034), the Security Scanner's
scan-submission screen (`/api/scanner/scan`, see ADR 0035/0036), and the
interactive lab terminal (`/api/labs/{id}/terminal`, see ADR 0039/0040).
Every other screen works exactly the same with or without it. Omit it and
those three screens show a plain "not configured on this build" message
instead of their real UI -- this is the same "optional integration
degrades gracefully, core functionality never blocked" pattern already
used for Turnstile/billing
providers on the web app, not a crash or fake data.

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
