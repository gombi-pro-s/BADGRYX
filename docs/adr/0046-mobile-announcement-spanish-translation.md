# ADR 0046: Spanish translation authoring for mobile org announcements

## Status

Accepted.

## Context

ADR 0043 named Spanish translation authoring
(`announcement_translations`, ADR 0038) as the one deliberately deferred
piece of the mobile org-announcements screen, since it is a second,
optional form section on top of an already-complete feature. Reading
`admin/announcements/actions.ts`'s `upsertSpanishTranslation()` (mirrored
identically in the org actions file) showed it needs nothing beyond what
the mobile form already has a save path for: both fields filled upserts
the `es` row, either left blank deletes it.

## Decision

- `lib/orgs/org_announcement.dart` gained
  `shouldUpsertSpanishTranslation(titleEs, bodyEs)`, the pure boolean this
  branch turns on (both fields non-empty), ported directly from
  `upsertSpanishTranslation()`'s own condition.
- `org_announcements_screen.dart`'s `OrgAnnouncementFormScreen`: two more
  `TextField`s in a bordered "Spanish translation (optional)" section,
  matching the web form's copy. `_load()` now also fetches the `es`
  translation row when editing; `_save()` calls a new
  `_upsertSpanishTranslation()` after the `announcements` write succeeds
  (needing the row's id back from `insert().select('id').single()` on
  create, where it previously discarded the response).

## Why

Reusing the exact same both-or-neither condition as the web action avoids
a second, independently-invented rule for when a translation "counts" --
the two apps' announcement CMSes now agree by construction, not by
convention.

## Consequences

- +4 `flutter test`s (`shouldUpsertSpanishTranslation`: both filled, title
  blank, body blank, both blank) -- 120 `flutter test`s total (was 116).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Closes ADR 0043's named gap. No web-only mobile gaps remain on the
  Organizations screen.
