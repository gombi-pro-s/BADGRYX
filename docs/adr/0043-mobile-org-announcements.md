# ADR 0043: Org announcement authoring in the Flutter mobile app

## Status

Accepted.

## Context

ADR 0041/0042 named org-scoped announcement authoring
(`/orgs/[orgId]/announcements`) as the one remaining deferred Organizations
feature. Reading `announcements/page.tsx`, `[announcementId]/page.tsx`, and
`actions.ts` showed the same shape as the rest of the org surface: plain
RLS-scoped Postgrest against the `announcements` table --
`announcements_write` (`20260922000024_announcements.sql`) already lets an
org's own instructors/team_owners/org_admins insert/update/delete rows
scoped to their org, so there is no Route Handler and no new RPC to wire up
here, same as the instructor dashboard.

The one piece of the web feature this ADR does **not** port is Spanish
translation authoring (`announcement_translations`, ADR 0038's
`title_es`/`body_markdown_es` fields). That's a second, optional form
section on top of an already-complete feature -- a real gap, named here and
in the mobile README rather than silently missing, not a blocker to
shipping the base feature.

## Decision

- `lib/orgs/org_announcement.dart`: `OrgAnnouncement` row parser plus two
  pure helpers ported directly from `announcements/page.tsx`'s inline
  ternary -- `isAnnouncementExpired()` and `announcementStatusLabel()`
  (expired wins over published, mirrored exactly).
- `lib/orgs/org_announcements_screen.dart`:
  - `OrgAnnouncementsScreen`: list of an org's announcements (title +
    status chip), a FAB to create a new one.
  - `OrgAnnouncementFormScreen`: one screen doing double duty as create
    and edit (Flutter navigation makes a single form-with-optional-id the
    natural unit, unlike the web's two separate pages) -- title, markdown
    body, an optional expiry (date+time picker), and, in edit mode, a
    published `SwitchListTile` and a delete action in the app bar, mirroring
    `PublishToggle`/`DeleteOrgAnnouncementButton` exactly.
- `org_detail_screen.dart` gained a second instructor-only button next to
  "Open instructor dashboard" -- "Announcements" -- behind the same
  `isOrgInstructorRole(myRole)` gate.

## Why

Combining create/edit into one screen avoids duplicating the same six form
fields across two widgets for a difference (an id) that Dart's own optional
parameters already express cleanly -- the web's two-page split exists
because Next.js routes `/announcements` (list+create) and
`/announcements/[id]` (edit) separately, not because the forms differ.

## Consequences

- +7 `flutter test`s (`org_announcement_test.dart`: `isAnnouncementExpired`
  x3, `announcementStatusLabel` x4 covering all four
  draft/published/expired combinations) -- 113 `flutter test`s total (was
  106).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Closes ADR 0041's last named Organizations gap. Spanish translation
  authoring for announcements remains web-only, named above.
