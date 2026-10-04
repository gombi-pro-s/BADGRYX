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
    Bearer token (see ADR 0039/0040). Real command-history recall
    (up/down arrow) too: the stock on-screen keyboard has no arrow keys,
    but a Bluetooth/USB keyboard or a software keyboard app that draws
    its own (e.g. Hacker's Keyboard) sends real hardware key events
    either way, which a `Focus` widget around the input field
    intercepts the same way `terminal.tsx`'s own `onKeyDown` does. See
    ADR 0050.
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
    - **Reports**: `/reports`'s equivalent -- write a pentest report or
      methodology write-up and ask the AI Mentor to critique it; separate
      from a capstone's reviewed submission and never affects your Skill
      Graph. Plain RLS-scoped Postgrest list/create/edit/delete, no Route
      Handler needed. "Ask Mentor to review" opens the general-mode
      Mentor screen rather than a true deep link into its
      `review_report`/`review_methodology` modes -- narrows, rather than
      closes, AI Mentor's own "no context deep links yet" gap below. See
      ADR 0052.
    - **AI Mentor**: `/mentor`'s equivalent, general-chat modes only
      (Explain/Hint/Teach/Analyze a failure -- no lab/lesson/finding/
      report deep links from mobile yet). Streams the exact same NDJSON
      `/api/mentor/chat` Route Handler `apps/web` calls, authenticated with
      an `Authorization: Bearer <session.accessToken>` header instead of a
      browser cookie (see ADR 0033); text streams into the reply bubble
      token-by-token, and the day's request quota is shown once a reply
      finishes. Needs a second, **optional** build-time config value --
      see Configuration below -- and degrades to a plain "not configured
      on this build" message if it's absent, rather than blocking the rest
      of the app.
    - **Security Scanner**: `/scanner`'s equivalent -- past scans plus a
      combined posture summary, a "New scan" screen that either pastes a
      single snippet or picks one or more real files (`file_picker`, the
      one new dependency outside `http`/`supabase_flutter`, since there's
      no SDK-only way to open a real file picker) and submits whichever
      through the same `Authorization: Bearer` path as the Mentor to
      `/api/scanner/scan` (see ADR 0033/0035/0048), and a scan-detail
      screen showing each finding (severity-coded, most-severe-first) with
      its evidence/explanation/impact/remediation, a status chip, real
      manual status-transition buttons
      (`transition_scan_finding_status()` RPC, plain RLS-scoped, no Route
      Handler -- see ADR 0044), and a real "Enrich with AI" button calling
      the now Bearer-authed `/api/scanner/findings/{id}/enrich` (see
      ADR 0045). No named gaps remain on this screen.
    - **Billing**: `/settings/billing`'s equivalent -- your real plan,
      subscription status, and every entitlement, straight from
      `subscriptions`/`plans`/`plan_entitlements` under the same RLS as
      the web app, no Route Handler needed for any of that, plus a real
      "Upgrade with Stripe/Paystack/Flutterwave" flow: a Bearer-authed
      POST to a new `/api/billing/checkout` (same provider calls as the
      web app's own checkout actions) hands back that provider's hosted
      checkout URL, shown in a copy-link dialog -- the same pattern as
      the Organizations screen's invite link -- to open in a browser;
      this app never touches card details either way. See
      ADR 0037/0047. Canceling or otherwise managing an existing
      subscription isn't built on either client -- that's the payment
      provider's own dashboard/customer portal, by the same provider-
      hosted-flow design as checkout, not a gap in this app.
    - **Organizations**: `/orgs` and `/orgs/[orgId]`'s equivalent -- your
      real memberships, a "Create organization" flow, the member roster
      (admins can change roles or remove members via the real
      `update_organization_member_role()`/`remove_organization_member()`
      RPCs; anyone can leave), and, for admins, a real invite-link flow
      (`create_organization_invitation()`) with revoke. For any
      instructor/team_owner/org_admin, two more real entry points: "Open
      instructor dashboard" -- every member's real graded results (skills
      proven/in progress, labs completed, quizzes passed, CTF solved,
      investigations passed), one card per member rather than the web's
      wide table, straight from the same six RLS-scoped queries the web
      page runs, no new RPC (ADR 0042) -- and "Announcements" -- a real
      list/create/edit/publish-toggle/delete screen for that org's own
      announcements, straight against the same `announcements` table and
      RLS the web CMS uses, plus an optional Spanish translation section
      (`announcement_translations`, same both-fields-or-neither rule as
      the web CMS) on the create/edit form (ADR 0043/0046). Plain
      RLS-scoped Postgrest/RPC throughout this whole screen, no Route
      Handler needed anywhere in Organizations.
    - **Admin**: shown only when `user_roles` says the signed-in user is
      staff (admin or moderator, mirroring `is_staff()` -- see ADR 0049),
      the first staff-only mobile screen. Today it holds two real flows:
      Platform Announcements (the same list/create/edit/publish-toggle/
      delete/Spanish-translation screen as Organizations' own
      announcements, scoped to `organization_id IS NULL` instead of one
      org, with the same `log_audit_event()` call on publish/unpublish
      the web admin action itself makes), and Users -- search any user
      by email/username/display name
      (`admin_search_users()`) and grant/revoke their instructor/
      moderator/admin roles (`grant_platform_role()`/
      `revoke_platform_role()`, each already audit-logging and
      re-checking `is_admin()` itself server-side; you can never revoke
      your own admin role). See ADR 0051. Every other `/admin/*` flow
      (learning paths, labs, quizzes, CTF challenges, CTF events, path
      import/export) has no mobile screen yet -- a real, deliberately
      broad gap, not silently missing.
- This is still a first vertical slice, not the whole web app. Future
  admin pillars belong behind "Admin" too, the same way every other
  pillar here lives behind "More" rather than as a new flat tab.

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
