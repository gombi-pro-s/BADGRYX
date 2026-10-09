# ADR 0064: Content translations for learning paths and lessons

## Status

Accepted.

## Context

ADR 0038 built `announcement_translations` -- an optional Spanish
translation row per announcement, RLS-scoped identically to the parent
row, rendered via the pure `pickAnnouncementText()` instead of the raw
English row when the viewer's locale is Spanish. `README.md` and
`RELEASE_CHECKLIST.md` have named "other user-authored content types
beyond announcements (paths, lessons, etc.) remain untranslated" as an
open gap ever since.

Learning paths and lessons are the next content types worth closing
that gap for: both are long-lived, staff-authored, and already have a
real Spanish-speaking audience path through `/learn`. Modules are
deliberately excluded -- a module only ever has a `title`, no body
text, and the admin UI doesn't even have an edit form for one (create-
only, matching the web admin's own limitation) -- so there's no second
field to translate and no form to add the fieldset to.

Auditing mobile's admin Learning Paths screen (ADR 0055) for parity
surfaced a real, previously undocumented, larger gap: mobile has no
locale-reading infrastructure anywhere in the app. Only admin/org
*authoring* screens ever write a translation row (`org_announcement.dart`'s
own `shouldUpsertSpanishTranslation()`); nothing on mobile -- including
the pre-existing `announcement_translations` feature from ADR 0038/0043
-- ever reads a user's locale preference or displays a translated row to
a learner. Mobile has no `/settings`-equivalent Language section and no
cookie/preference store for a locale at all. This means every Spanish
translation ever authored via mobile's own forms has always been
invisible on mobile itself, only ever visible through the web app. This
phase does not fix that: building a locale switcher and a device-side
read path for every translated content type is a separate, larger
decision (a new settings screen, a storage choice, and auditing every
screen that renders translatable content), not something to fold
silently into a content-translations phase. It's named here and in
`RELEASE_CHECKLIST.md` as its own gap instead.

## Decision

- `supabase/migrations/20260922000032_content_translations.sql`:
  `learning_path_translations` (`path_id`, `locale` CHECK IN ('en',
  'es'), `title` NOT NULL, `description` nullable, unique
  `(path_id, locale)`, ON DELETE CASCADE) and `lesson_translations`
  (`lesson_id`, `locale`, `title` NOT NULL, `content_markdown` NOT NULL,
  unique `(lesson_id, locale)`, ON DELETE CASCADE), each with RLS
  mirroring its parent's own `_select_published_or_staff`/
  `_staff_write` policies through an `EXISTS` against the parent row --
  the same pattern `announcement_translations` uses.
- `apps/web/src/lib/i18n/content-translation.ts`: `pickPathText()` and
  `pickLessonText()`, both mirroring `pickAnnouncementText()` exactly
  (fall back to the base row when the locale is the default or no
  translation row matches).
- Admin forms (`admin/paths/create-path-form.tsx`/`edit-path-form.tsx`
  and the lesson equivalents): the same "Spanish translation (optional)"
  fieldset `edit-announcement-form.tsx` already has, gated by two
  different rules depending on whether the base row's secondary field
  is itself nullable:
  - Paths: `upsertPathSpanishTranslation()` requires only a non-empty
    `title_es` (a path's own `description` is optional, so its
    translation can be too).
  - Lessons: `upsertLessonSpanishTranslation()` requires both
    `title_es` and `content_markdown_es` (a lesson's own
    `content_markdown` is NOT NULL, so a translation with no body would
    be a broken row, not a partial one) -- the same both-fields-or-
    neither rule `shouldUpsertSpanishTranslation()` already encodes for
    announcements.
- Learner-facing `/learn`, `/learn/[pathId]`, and the lesson-reading
  page `/learn/[pathId]/[moduleId]/[lessonId]` all fetch the matching
  `_es` translation row(s) alongside the base content and render
  `pickPathText()`/`pickLessonText()`'s result instead of the raw row,
  the same substitution `/dashboard` already does for announcements.
- Mobile (`admin_paths_screen.dart`): admin-authoring parity only, per
  the Context above -- the path and lesson edit screens gained the same
  two-field Spanish translation section, wired to the same
  `learning_path_translations`/`lesson_translations` tables with the
  same upsert-or-delete-on-blank gates, re-using
  `shouldUpsertSpanishTranslation()` for the lesson form (both fields
  required) and a path-specific title-only gate for the path form. No
  mobile screen reads or displays either table -- consistent with every
  other translation table on mobile today, not a new limitation
  introduced here.

## Why

Mobile's scope is capped at authoring parity rather than silently
expanded into building a locale switcher, because that UI doesn't exist
for *any* content type yet (not even the two-release-old
`announcement_translations`), and building one well -- deciding where a
user sets their language, how it's stored, and auditing every
translatable screen -- is a bigger decision than "add two tables." It's
honest to ship admin parity now and name the read-side gap plainly
rather than pretend this phase closes it, or quietly skip mobile
entirely.

## Consequences

- +11 SQL assertions (`supabase/tests/028_content_translations.sql`):
  staff-write/plain-user-cannot, published-readable, unpublished-staff-
  only, uniqueness, and cascade delete, for both tables. All SQL tests
  (through 028) pass via `scripts/run-sql-tests.sh`.
- Web: +7 `vitest` tests for `pickPathText()`/`pickLessonText()` -- 323
  total. `tsc --noEmit` and ESLint clean, `npm run build` succeeds.
- Mobile: no new pure logic, so no new `flutter test`s -- 213 total,
  unchanged. `flutter analyze` clean, `flutter test` passes, `flutter
  build web` succeeds both with and without `API_BASE_URL`.
- Closes the "other user-authored content types beyond announcements"
  gap in `README.md`/`RELEASE_CHECKLIST.md` for paths and lessons
  specifically (modules remain out of scope, by design -- see Context).
- Opens a new, previously unnamed gap: mobile has no locale-reading
  infrastructure anywhere, so no translation table -- this one or
  `announcement_translations` -- is ever visible on mobile itself.
  Named in `RELEASE_CHECKLIST.md`/`mobile/app/README.md` as its own
  item, not bundled into this phase.
