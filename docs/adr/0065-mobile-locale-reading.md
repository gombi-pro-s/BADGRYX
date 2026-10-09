# ADR 0065: Mobile locale-reading infrastructure (Language setting)

## Status

Accepted.

## Context

ADR 0064 named a real gap while auditing mobile's Learning Paths admin
screen for translation parity: mobile has no locale-reading
infrastructure anywhere. Only admin/org authoring screens ever write a
translation row; nothing on mobile ever reads a user's locale
preference or renders a translated row to a learner. That made every
Spanish translation ever authored through a mobile form -- the
pre-existing `announcement_translations` (ADR 0038/0043) and this
phase's own `learning_path_translations`/`lesson_translations`
(ADR 0064) -- invisible on mobile itself, visible only through the web
app.

Closing it means answering three questions web's own `lib/i18n/`
(ADR 0025) already answered for the browser case:

1. Where does a user set their language? Web has `/settings`'s Language
   section. Mobile has no Profile/Security/Privacy/Settings screen at
   all -- those were never built (Billing already exists as its own
   "More" entry; a profile-editing screen remains a separate, unnamed
   gap this ADR doesn't claim to close). Rather than invent a generic
   "Settings" hub implying screens that don't exist, this phase adds a
   single, plainly-named "Language" entry to the existing "More" menu.
2. How is the choice persisted? Web uses a cookie, read on every
   server-rendered request. Mobile has no server-rendered request to
   attach a cookie to. `shared_preferences` is already a transitive
   dependency (`supabase_flutter` uses it to persist the auth session
   across restarts) -- declaring it directly and using the same
   mechanism for one more string needs no new dependency, the same
   "already present, no reasonable hand-rolled alternative" reasoning
   `http`/`crypto` were promoted on.
3. Which screens read it back? Only the two content types that already
   have a translation table with real authored data: the Dashboard's
   announcements, and Learn (paths list, path detail's lesson list, and
   the lesson viewer).

This app still has no global state management library (no Provider,
Riverpod, etc.), and this phase doesn't add one. A screen reads the
stored locale once per load, exactly like a web server component calls
`getLocale()` once per request -- changing the Language setting takes
effect the next time a screen reloads (a push-route screen like Learn's
path/lesson detail reloads fresh every time you navigate into it; the
Dashboard tab, kept alive in the bottom nav's `IndexedStack`, needs its
existing pull-to-refresh). This mirrors web's own cookie model, where
`setLocaleAction` only revalidates the current path, not every open tab.

## Decision

- `pubspec.yaml`: `shared_preferences` promoted from transitive to
  direct dependency.
- `lib/i18n/locale.dart` (new): `supportedLocales`/`defaultLocale`/
  `isSupportedLocale()` mirror `lib/i18n/locales.ts` exactly.
  `LocaleStore.getLocale()`/`.setLocale()` wrap `shared_preferences`
  under the key `icorepen_locale`, falling back to `defaultLocale` for
  a missing or unrecognized stored value -- the same fallback
  `getLocale()` applies to a missing or unrecognized cookie.
- `lib/settings/language_screen.dart` (new): a plain radio-button
  picker (English/Español), wrapped in `RadioGroup<String>` (not bare
  `RadioListTile`s -- see ADR 0063's own note on the deprecated
  ungrouped form). Wired into `lib/home/more_screen.dart` as a
  "Language" entry.
- `lib/dashboard/announcement.dart`: `AnnouncementTranslation` +
  `pickAnnouncementText()`, a direct port of `lib/i18n/
  announcement-translation.ts`'s function of the same name.
  `dashboard_screen.dart`'s `fetchDashboard()` now also reads the stored
  locale and the matching `announcement_translations` rows (skipped
  entirely when there are no announcements), the same second
  round-trip `dashboard/page.tsx` makes rather than a join.
- `lib/learn/lesson.dart`: `LearningPathTranslation`/`pickPathText()`
  and `LessonTranslation`/`pickLessonText()`, direct ports of
  `lib/i18n/content-translation.ts`'s functions of the same names.
  `learn_screen.dart`'s `fetchLearningPaths()`, the path detail
  screen's `_load()`, and the lesson viewer's `_load()` all read the
  stored locale and the matching translation rows, applying the pick
  functions everywhere a title/description/content currently renders
  the raw base row -- the path list, the path detail header and its
  lesson list, and the lesson viewer's own title/content/Mentor
  `focusTitle`.

## Why

A per-screen read rather than a global locale provider: this app has
never introduced app-wide reactive state for anything, including far
more frequently-changing data (skill states, announcements). Adding one
just for a setting that changes rarely and already has an honest,
documented "picked up on next reload" model (matching web's own
per-request cookie read) would be new architecture for a problem this
app's existing FutureBuilder-per-screen pattern already handles
adequately.

## Consequences

- +13 `flutter test`s (3 `locale_test.dart`, 3 `pickAnnouncementText`
  cases, 7 `pickPathText`/`pickLessonText` cases) -- 226 total (was
  213). `flutter analyze` clean, `flutter build web` succeeds both with
  and without `API_BASE_URL`.
- Closes the mobile locale-reading gap named in ADR 0064/
  `RELEASE_CHECKLIST.md`/`mobile/app/README.md` for announcements,
  learning paths, and lessons -- the three content types with a real
  translation table and real authored data today.
- Does not add a Profile/Security/Privacy settings screen; "Language"
  is added standalone to "More" rather than folded into a Settings hub
  that doesn't otherwise exist on mobile. If a general Settings screen
  is ever built, this entry is a natural candidate to move under it.
