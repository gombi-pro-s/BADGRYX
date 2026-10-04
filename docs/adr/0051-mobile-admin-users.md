# ADR 0051: Admin Users (role management) screen on mobile

## Status

Accepted.

## Context

ADR 0049 opened the Admin section of the mobile app with one flow
(Platform Announcements) and named every other `/admin/*` section as a
real, deliberately broad remaining gap. Reading `admin/users/page.tsx` +
`actions.ts` + `role-toggle.tsx` + `user-search.tsx` showed the whole
flow is three RPCs -- `admin_search_users()`, `grant_platform_role()`,
`revoke_platform_role()` -- each a `SECURITY DEFINER` function that
re-checks `is_admin()` and audit-logs itself
(`20260922000016_admin_user_role_management.sql`). `requireAdmin()` on
the web side is a convenience early-return, not the authorization
boundary; the RPCs are. That makes this screen safe to build with no
Route Handler and no new client-side authorization logic beyond the
same `isStaffRole()` gate the Admin section's entry point already uses
-- the second-smallest possible admin screen after announcements.

## Decision

- `lib/admin/admin_user.dart` (new): `AdminUserSearchResult` (parses
  `admin_search_users()`'s row shape) with a `label` getter mirroring
  `user-search.tsx`'s `display_name ?? username ?? email ?? user_id`
  fallback chain; `grantableRoles` (mirrors `GRANTABLE_ROLES`: instructor/
  moderator/admin, never `user`); and the pure
  `isRoleToggleDisabled()` mirroring `role-toggle.tsx`'s inline
  `role === "admin" && user.user_id === currentAdminId` check --
  `revoke_platform_role()` refuses this server-side regardless, but the
  UI disables the toggle rather than letting a tap round-trip into an
  error it already knows is coming.
- `lib/admin/admin_users_screen.dart` (new): a search box calling
  `admin_search_users`, then one `Card` per result with a `FilterChip`
  per grantable role, calling `grant_platform_role`/`revoke_platform_role`
  on toggle with the same optimistic-update-then-revert-on-failure
  pattern `role-toggle.tsx`'s `useState`/`catch` does.
- `lib/admin/admin_screen.dart` gained a "Users" entry alongside
  "Platform Announcements".

## Why

Toggling the local `roles` list optimistically (rather than re-running
the whole search after every grant/revoke) matches the web app's own
UX reasoning exactly: a role change is near-instant in the common case,
and reverting the one row that failed is cheaper and clearer than
re-fetching everything.

## Consequences

- +10 `flutter test`s (`AdminUserSearchResult.fromRow` parsing + its full
  four-deep label fallback chain, `grantableRoles`'s exact three roles,
  `isRoleToggleDisabled`'s three cases) -- 151 `flutter test`s total (was
  141).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Narrows the Admin section's remaining gap to learning paths, labs,
  quizzes, CTF challenges, CTF events, path import/export, and report
  moderation -- still real, still named.
