# ADR 0049: First staff Admin screen on mobile -- Platform Announcements

## Status

Accepted.

## Context

Every mobile phase so far ported a learner- or org-facing web feature;
`RELEASE_CHECKLIST.md`'s "Everything else on mobile" line has named "every
other admin/instructor CMS flow has no mobile screen at all" since the
app's very first phase (ADR 0026). With the Scanner, Billing, and
Organizations gaps all closed (ADR 0045/0047/0048), this is the first
staff-only (`is_staff()`: admin or moderator) surface built on mobile.

Reading `admin/announcements/page.tsx` + `actions.ts` showed it is nearly
identical to the already-built `orgs/[orgId]/announcements` screen --
same `announcements` table, same create/edit/publish-toggle/delete shape,
same optional Spanish translation section -- the only real differences
are `organization_id IS NULL` instead of a specific org id, `requireAdmin()`
instead of `requireOrgInstructor()`, and a `log_audit_event()` RPC call on
the publish toggle that the org-scoped version doesn't make. That made
Platform Announcements the natural first admin screen to port: it reuses
nearly everything already built rather than opening an entirely new kind
of screen.

`/admin`'s own route guard is Next.js middleware, which mobile has no
equivalent of. The web app's real authorization boundary is RLS/
`requireAdmin()` regardless of what the middleware shows or hides, so
gating the mobile entry point by reading `user_roles` directly (mirroring
`getUserRoles()`/`is_staff()`) is exactly as safe: a wrong client-side
answer could only ever hide a real button, never grant a real permission.

## Decision

- `lib/auth/roles.dart` (new): `fetchUserRoles()` (plain `user_roles`
  select, scoped by its own `user_roles_select_own_or_admin` RLS policy)
  and the pure `isStaffRole()` mirroring `is_staff()` exactly (admin or
  moderator).
- `lib/admin/admin_announcements_screen.dart` (new): the platform-wide
  twin of `org_announcements_screen.dart`, reusing `OrgAnnouncement` and
  its pure helpers (`announcementStatusLabel`, `shouldUpsertSpanishTranslation`)
  as-is -- the model has no org-specific fields. Queries/mutations use
  `.isFilter('organization_id', null)` instead of `.eq('organization_id', orgId)`,
  and the publish toggle also calls the `log_audit_event()` RPC (already
  granted to `authenticated`), matching `toggleAnnouncementPublishedAction()`'s
  own `logPublishToggle()` call that the org-scoped action doesn't make.
- `lib/admin/admin_screen.dart` (new): a plain list of admin sections,
  today holding only "Platform Announcements" -- every other `/admin/*`
  flow (learning paths, labs, quizzes, CTF challenges, users, CTF events,
  path import/export, report moderation) has no mobile screen yet, named
  here and in the mobile README as a real, deliberately broad remaining
  gap.
- `lib/home/more_screen.dart`: converted from `StatelessWidget` to
  `StatefulWidget`, fetches the signed-in user's roles once in
  `initState()`, and appends an "Admin" entry only when `isStaffRole()`
  is true.

## Why

Reusing `OrgAnnouncement` for a platform-wide row avoids duplicating an
identical model under a new name just because its web counterpart lives
under `/admin` instead of `/orgs/[orgId]` -- the table, columns, and every
pure helper over them are genuinely the same regardless of which
`organization_id` scope wrote them.

## Consequences

- +5 `flutter test`s (`isStaffRole`: admin, moderator, plain user, an
  org-scoped role alone (not platform staff), no roles) -- 130
  `flutter test`s total (was 125).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Opens the Admin section of the app for the first time. Every other
  `/admin/*` flow remains a named, not-silently-missing gap.
