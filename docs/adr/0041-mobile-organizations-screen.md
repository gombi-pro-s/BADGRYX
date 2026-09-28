# ADR 0041: Organizations screen in the Flutter mobile app

## Status

Accepted.

## Context

Every mobile screen built so far serves an individual learner. Orgs are
the platform's other real dimension -- teams of learners under an
instructor/team_owner/org_admin hierarchy (ADR 0011). Reading
`orgs/page.tsx`, `orgs/[orgId]/page.tsx`, and `lib/auth/org.ts` showed
this surface is, like most of this app's learner-facing screens, plain
RLS-scoped Postgrest and a handful of RPCs
(`create_organization_invitation`, `update_organization_member_role`,
`remove_organization_member`) -- no Route Handler, no Bearer auth needed,
unlike Mentor/Scanner/the lab terminal.

Two real pieces of that web surface don't belong in this first mobile
slice: the **instructor dashboard** (`/orgs/[orgId]/dashboard`, real
per-member progress across quizzes/labs/CTF/investigations) is a
substantial reporting UI in its own right, not an extension of org
membership management; and **org-scoped announcement authoring**
(`/orgs/[orgId]/announcements`) already has a real web CMS (ADR 0038 just
extended it with translations) that a phone-sized form wouldn't improve
on. Both are named gaps, not silently missing.

## Decision

- `lib/orgs/organization.dart`: `Organization`/`OrganizationMember`/
  `OrganizationInvitation` row parsers, and pure helpers mirroring the web
  page's own logic exactly: `isOrgAdminRole()`/`isOrgInstructorRole()`
  (the `ADMIN_ROLES`/`INSTRUCTOR_ROLES` arrays), `formatOrgRole()` (the
  `role.replace("_", " ")` calls used throughout), and
  `invitationStatus()` (the revoked/accepted/expired/pending ternary from
  `orgs/[orgId]/page.tsx`).
- `lib/orgs/orgs_list_screen.dart`: the user's own memberships (mirroring
  `getUserOrganizations()`'s two-query pattern exactly) plus a real
  "Create organization" dialog -- a plain `organizations` insert; the
  existing `handle_new_organization` trigger makes the creator its
  `team_owner`, identical to the web flow.
- `lib/orgs/org_detail_screen.dart`: role badge, the member roster (an
  admin can change any member's role or remove them via the real RPCs;
  anyone can leave), and, for admins, a real invite-link flow
  (`create_organization_invitation`, shown once with a copy action) and
  an invitations list with revoke. A plain member's own query for
  `organization_invitations` genuinely returns empty here too -- that's
  `org_invitations_select_org_admin` doing its job, not routed around
  client-side, the same RLS-is-the-boundary discipline every other screen
  in this app follows.
- Wired into `MoreScreen`'s menu.

## Why

- **No Bearer auth needed** here, unlike the three most recent mobile
  phases (Mentor, Scanner, the lab terminal) -- a useful reminder that
  not every remaining mobile gap needs the Route Handler pattern; some
  are exactly the RLS-scoped Postgrest/RPC shape every earlier mobile
  screen already used.
- **Naming the instructor dashboard and org announcements as deferred**,
  rather than attempting a compressed version of either, keeps this
  phase's claim honest: real membership/invitation management, not a
  full instructor console.

## Consequences

- +12 unit tests (`organization_test.dart`: row parsing for all three
  types, `isOrgAdminRole()`/`isOrgInstructorRole()`'s role sets,
  `formatOrgRole()`, and `invitationStatus()`'s four precedence cases) --
  101 `flutter test`s total (was 89).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- No new dependency (`Clipboard` is part of Flutter's own
  `flutter/services.dart`, not a package).
- The instructor dashboard (real member progress) and org-scoped
  announcement authoring remain web-only, named gaps.
