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
    ADR 0050. A "Mentor" button next to the lab's title deep-links into
    AI Mentor's own `hint` mode for this lab, same as `/labs/[labId]`'s
    own Mentor link (see ADR 0059).
  - **Skills**: `/skills`'s equivalent -- your own skill list with its
    real, per-user state, read live from `skills` and `user_skill_states`
    under the exact same RLS this repo's SQL tests already prove.
  - **CTF**: `/ctf`'s equivalent -- published challenges
    (`ctf_challenges_public`, flag hash never exposed) and a real flag
    submit calling the same `submit_ctf_flag()` RPC the web app calls --
    correct/incorrect is never decided client-side. Shows each
    challenge's `current_points`, not its static `points` -- for a
    dynamic-scoring event's challenge the two can differ as more
    competitors solve it, and this screen displays exactly what
    `submit_ctf_flag()` would actually award right now, both calling the
    same `ctf_challenge_current_points()` (see ADR 0062). This is still
    only the flat challenge list, though -- web's whole Arena/mission UI
    (event grouping, live/upcoming/ended badges, countdown, leaderboard;
    ADR 0021) has no mobile counterpart at all, a real gap named here
    rather than silently carried forward. A "Mentor" button on
    a challenge's own detail screen deep-links into `hint` mode for that
    challenge (ADR 0059).
  - **More**:
    - **Investigate**: `/investigate`'s equivalent -- real case evidence
      artifacts, a mixed multiple-choice/exact-text answer form graded
      server-side via `submit_investigation_answers()`, and a private,
      debounced-autosave notes scratchpad (not even staff can read it). A
      "Mentor" button deep-links into `guide_investigation` mode for this
      investigation (ADR 0059).
    - **Learn**: `/learn`'s equivalent -- published paths grouped by
      module, each lesson row showing "Read" once `lesson_progress`
      records it or its estimated minutes otherwise, and a lesson viewer
      with a "Mentor" button that finally gives the `lesson` context deep
      link (ADR 0059) somewhere to attach. Lesson content renders as
      plain text, not rendered Markdown -- no markdown-rendering package
      exists anywhere in this app yet, and every other `*_markdown` field
      (announcements, reports, the admin lesson editor) is shown the same
      way, so this stays consistent rather than introducing the app's
      first one. A linked, published quiz embeds right on the lesson
      screen and grades through the real `submit_quiz_attempt()` RPC,
      same single-choice-only-even-for-`multi_choice` limitation
      `quiz-attempt.tsx` has on web. Plain RLS-scoped Postgrest/RPC, no
      Route Handler. See ADR 0060.
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
      Handler needed. "Ask Mentor to review" deep-links into
      `review_report`/`review_methodology` (whichever matches this
      report's own kind, mirroring `[reportId]/page.tsx`'s own
      `mentorMode` computation) -- closes the gap ADR 0052 named. See
      ADR 0059.
    - **AI Mentor**: `/mentor`'s equivalent. General-chat modes (Explain/
      Hint/Teach/Analyze a failure) are reachable from anywhere via
      "More," and six pillars now deep-link into their own
      context-specific mode -- Labs/CTF (`hint`), Investigate
      (`guide_investigation`), the Scanner's finding cards
      (`explain_finding`), Reports (`review_report`/
      `review_methodology`), and Learn's lesson viewer (`teach`) -- the
      same modes `/api/mentor/chat` and `buildMentorContext()` already
      supported server-side; the gap was only ever that this screen
      hard-coded `contextType: 'general'` and offered a four-mode
      picker. No named Mentor context remains missing a deep link.
      Opening any context's chat also resumes its own most-recently-
      updated conversation (a direct port of `/mentor/page.tsx`'s own
      `existingConversation` lookup against `mentor_conversations`/
      `mentor_messages`, plain RLS-scoped Postgrest reads, no Route
      Handler) rather than always starting fresh -- `/api/mentor/chat`
      itself never upserts by context, it only reuses a conversation the
      caller already has the id for, exactly as web's own client does
      once that initial lookup has run. No named Mentor gap remains on
      mobile. See ADR 0059/0060/0061. Streams the exact same NDJSON
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
      Handler -- see ADR 0044), a real "Enrich with AI" button calling
      the now Bearer-authed `/api/scanner/findings/{id}/enrich` (see
      ADR 0045), and an "Ask Mentor" button deep-linking into
      `explain_finding` mode for that finding (ADR 0059). No named gaps
      remain on this screen.
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
      the first staff-only mobile screen. Today it holds six real flows:
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
      your own admin role). See ADR 0051. Also CTF Challenges (create/
      edit, category/difficulty/event/points, an optional Min points
      floor for dynamic-scoring events (defaults to half of Points when
      left blank, validated `<= Points`, see ADR 0062), a flag field
      hashed to
      lowercase hex SHA-256 on-device with `package:crypto` the moment you
      submit -- byte-identical to `apps/web`'s own server-side
      `hashFlag()`, never stored or shown as plaintext again -- publish
      toggle, and an inline skill tagger) and CTF Events (create/edit,
      scoring type -- the Dynamic option's own help text now explains the
      real decay-to-a-floor behavior ADR 0062 built, not "not implemented
      yet" -- optional start/end times, publish toggle, and a
      read-only list of the event's own challenges), both plain
      RLS-scoped Postgrest CRUD on `is_staff()`-gated tables, no Route
      Handler needed, no delete action either (same as the web admin UI
      for both). See ADR 0053. Also Quizzes -- create (no edit form for a
      quiz's own fields, matching the web admin UI, which doesn't have one
      either), a publish toggle, an inline skill tagger, and a questions
      manager (existing questions with their choices and a Remove button,
      plus an add-question form that only ever creates `single_choice`
      questions with a growable choice list -- the same restriction
      `questions-manager.tsx` has -- validated the same way it is: at
      least two non-empty choices, at least one marked correct). See
      ADR 0054. Also Learning Paths -- create/edit a path (title/slug/
      description, publish toggle), create modules under it (no module
      edit form, matching the web admin UI, which doesn't have one either
      -- only a publish toggle and its own lessons), and create/edit
      lessons under a module (title/slug/summary/content/estimated
      minutes, publish toggle, and an inline skill tagger for
      `lesson_skills`). `order_index` stays at its schema default on
      every insert here too, same as the web, which has no reordering
      control anywhere. See ADR 0055. Also Labs -- create/edit (title/
      slug/category/difficulty/minutes/points/description, publish
      toggle, inline skill tagger), a hints manager (level 1-5, point
      cost, add/remove), and a flags manager (label, variant seed, a
      plaintext field hashed to lowercase hex SHA-256 on-device with the
      same `hashCtfFlag()` ADR 0053 built, add/remove), and, closing the
      one gap ADR 0056 named, a terminal environment editor: existing
      environments list/load-into-editor/remove via plain Postgrest
      (`lab_environments_staff_only` is staff-read too, not just
      staff-write), and a variant-seed-plus-JSON-spec form whose "Save
      environment" button POSTs to a new Bearer-authed
      `/api/admin/labs/{labId}/environments` -- it re-validates the spec
      against `lib/terminal/spec.ts`'s `environmentSpecSchema` (the same
      schema `lib/terminal/execute.ts` parses it with) before upserting,
      so the two clients can never save a spec with different rules. See
      ADR 0057. And, closing the last named `/admin/*` gap, path
      import/export: an "Export" button on a path's detail screen GETs a
      new Bearer-authed `/api/admin/paths/{pathId}/export` (moved there
      from `/admin/paths/{pathId}/export` -- that prefix is one of the
      web app's proxy-level protected routes, which would otherwise
      redirect an unauthenticated mobile caller to an HTML login page
      before its own Bearer check ever ran) and shows the bundle JSON in
      a copy-to-clipboard dialog; an "Import a path" button opens a
      paste-JSON screen that POSTs to a new `/api/admin/paths/import`, a
      JSON adapter around the exact same `importPathBundle()` orchestration
      the web Server Action calls (never a second Dart implementation of
      that multi-step insert-with-rollback logic). See ADR 0058. Every
      `/admin/*` pillar this app has ever named as a gap is now closed.
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
**it's optional**. It's only needed for the screens that call that
deployment's Route Handlers directly rather than talking to Supabase --
AI Mentor (`/api/mentor/chat`, see ADR 0033/0034), the Security Scanner's
scan-submission screen (`/api/scanner/scan`, see ADR 0035/0036), the
interactive lab terminal (`/api/labs/{id}/terminal`, see ADR 0039/0040),
the Billing screen's "Upgrade with..." checkout buttons
(`/api/billing/checkout`, see ADR 0037/0047), the admin Labs screen's
"Save environment" button (`/api/admin/labs/{labId}/environments`, see
ADR 0057), and the admin Learning Paths screen's Export/Import buttons
(`/api/admin/paths/{pathId}/export` and `/api/admin/paths/import`, see
ADR 0058). Every other screen works exactly the same with or without it.
Omit it and each of those shows a plain "not configured on this build"
message (or, for the Labs environment editor specifically, keeps
view/delete working and only disables the save form) instead of its real
UI -- this is the same "optional integration degrades gracefully, core
functionality never blocked" pattern already used for Turnstile/billing
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
