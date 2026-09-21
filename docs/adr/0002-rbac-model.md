# ADR 0002: Two-tier RBAC — platform roles + organization roles

## Status

Accepted.

## Context

The product needs both platform-wide roles (a moderator or admin who can
act across the whole product) and organization/team-scoped roles (an
instructor or team_owner who has authority only within their own
organization's data — e.g. viewing their students' skill progress).

## Decision

- `user_roles(user_id, role)` holds platform-wide roles:
  `user | instructor | moderator | admin`. Every user implicitly has
  `user`; elevated roles require an explicit grant.
- `organization_members(organization_id, user_id, role)` holds
  organization-scoped roles: `member | instructor | team_owner | org_admin`.
  These grant authority only within that organization.
- `profiles` never stores a role column. Role data lives only in the two
  tables above, both RLS-protected so a user can read their own role
  assignments but can never write them (except an admin, or the org's own
  admin for org-scoped roles).
- Two `SECURITY DEFINER` helper functions, `has_role()`/`is_admin()`/
  `is_staff()` and `is_org_admin()`/`is_org_member()`, are the only way RLS
  policies check role membership. They always key off `auth.uid()`
  (`SECURITY DEFINER` running with owner privileges only bypasses RLS on the
  role table -- it never accepts a caller-supplied user id), so they cannot
  be used to probe another user's roles or to check an arbitrary user's
  authority from a different session.

## Why

Storing role on `profiles` (a table users can update themselves) would make
privilege escalation a one-line RLS mistake away. Splitting role into its
own table with no client write path, and only reading it through
`SECURITY DEFINER` functions, makes "can this user do X" a single audited
code path instead of scattered `profile.role === 'admin'` checks that a
client could spoof.

## Consequences

- Any new elevated-permission feature should reuse `is_admin()`/
  `is_staff()`/`is_org_admin()` rather than inventing a new ad hoc check.
- Granting a role always goes through an admin action (or `service_role`),
  which is auditable via `log_audit_event()`.
- See `supabase/tests/001_identity_rls.sql` for the regression tests
  proving a user cannot self-grant, cannot escalate via UPDATE, and cannot
  read another user's role assignments.
