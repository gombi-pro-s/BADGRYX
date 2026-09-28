# ADR 0042: Instructor dashboard in the Flutter mobile app

## Status

Accepted.

## Context

ADR 0041 named the instructor dashboard (`/orgs/[orgId]/dashboard`, real
per-member progress) as a deliberately deferred piece of the
Organizations screen -- a substantial feature in its own right, not an
extension of membership management. Reading `dashboard/page.tsx` showed
it is, like the rest of the org surface, plain RLS-scoped Postgrest: six
queries (`profiles`, `user_skill_states`, `lab_progress`,
`quiz_attempts`, `ctf_submissions`, `investigation_submissions`), all
already scoped to exactly this org's members by the instructor's own RLS
session (see `20260922000012_org_instructor_visibility_and_invitations.sql`),
then one inline aggregation into a per-member stats row. No Route
Handler, no new RPC.

## Decision

- `lib/orgs/instructor_dashboard.dart`: `MemberStats` and the pure
  `computeMemberStats()` function, a direct port of `dashboard/page.tsx`'s
  inline `.map()` -- for each member, `PROVEN_STATES`/`IN_PROGRESS_STATES`
  filtered skill-state counts, `lab_progress`/`quiz_attempts`/
  `ctf_submissions`/`investigation_submissions` filtered-and-counted by
  `user_id`, and the same `display_name` -> `username` -> raw id name
  fallback.
- `lib/orgs/instructor_dashboard_screen.dart`: fetches the same six
  queries, calls `computeMemberStats()`, and renders one card per member
  (stat labels in a `Wrap`) rather than the web's 8-column table --
  there's no room for that table on a phone, so this is a real, different
  layout for the same data, not a compressed table.
- `org_detail_screen.dart` gained an "Open instructor dashboard" button,
  visible only when `isOrgInstructorRole(myRole)` is true -- the same
  gate `orgs/[orgId]/page.tsx`'s own `isInstructor` link uses.

## Why

Porting the aggregation as one pure function, tested against the same
"scoped to only this member's rows" and "no rows anywhere still returns
zero, not an error" cases the web logic implicitly relies on, is the same
discipline every other ported helper in this app has followed (
`pickAnnouncementText`, `aggregatePosture`, `computeMemberStats` here).
A card-per-member layout is the honest mobile equivalent of the web's
table -- same data, real information hierarchy for a narrow screen,
not an attempt to literally reproduce eight columns.

## Consequences

- +5 unit tests (`instructor_dashboard_test.dart`: single-member full
  aggregation, cross-member scoping, both name-fallback branches, an
  all-zero member, and an empty org) -- 106 `flutter test`s total (was
  101).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Closes the instructor-dashboard half of ADR 0041's named gap. Org-scoped
  announcement authoring remains the one still-deferred org feature.
