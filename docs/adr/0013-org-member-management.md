# ADR 0013: Org member management — a live "last team owner" invariant

## Status

Accepted.

## Context

`organization_members` already had real RLS support for changing a
member's role or removing them (`org_members_update_org_admin`,
`org_members_delete_org_admin_or_self`, in
`20260921000005_identity_rls_policies.sql`) — the gap flagged in
`RELEASE_CHECKLIST.md` was purely a missing UI. Building that UI is exactly
the moment to ask what the RLS policies *don't* enforce: nothing stopped an
`org_admin` from demoting or removing the organization's only
`team_owner`. RLS policies check "is the caller allowed to touch this row,"
not "does the org still have someone who can manage it afterward" — that's
a cross-row invariant, which a row-level policy structurally can't express.
Left alone, this UI would have made a real, previously only
theoretical/inconvenient gap trivially easy to trigger by accident (a
misclick on the wrong member's role dropdown).

## Decision

`update_organization_member_role(p_organization_id, p_organization_member_id, p_new_role)`
and `remove_organization_member(p_organization_id, p_organization_member_id)`
are the two new `SECURITY DEFINER` functions this app's own UI is built on
— mirroring `grant_platform_role()`/`revoke_platform_role()`
(ADR-adjacent, `20260922000016_admin_user_role_management.sql`): one
function per write, each re-checks authorization itself
(`is_org_admin()`, or — for removal only — the caller removing their own
membership), each is audit-logged, and each adds the state-transition
guard the raw RLS policies can't express.

The guard: before demoting a `team_owner` to any other role, or removing a
`team_owner`, count how many `team_owner` rows the organization currently
has. If the row being changed is the only one, reject with a clear error.
This is a **live count**, not a self-check — it blocks an `org_admin` from
demoting/removing a *different* member who happens to be the sole owner
just as much as it blocks the owner from doing it to themselves, and it
stops blocking the instant a second `team_owner` exists. That's a
different (and stricter) invariant than `revoke_platform_role()`'s
"cannot revoke your OWN admin role," which is a pure self-check regardless
of how many other admins exist platform-wide — the org invariant needed
to be about the *organization's* remaining capacity to be managed, not
about who's making the call.

The raw RLS write path on `organization_members` is left in place, same
reasoning as every prior "narrow to one function" decision in this
schema: `service_role` tooling, migrations, and fixture setup still use it
directly, and this app's own UI simply never calls anything else.

## Why

An invariant that "should" hold but isn't actually enforced is a bug
waiting for the first UI that makes the forbidden action easy to trigger.
This is the same category of finding as ADR 0012's dangling FK columns:
discovered by building the real feature and asking what could go wrong,
not by an abstract audit.

## Consequences

- `supabase/tests/019_org_member_management.sql` proves: a plain member
  can't change anyone's role or remove someone else, but can remove
  (leave) themselves; an org_admin/team_owner from an unrelated
  organization has zero authority here; a real org_admin can promote/
  demote a member and it's audit-logged; the last `team_owner` cannot be
  demoted or removed by anyone, including themselves; and once a second
  `team_owner` exists, the first one can be freely demoted or removed
  again.
- `/orgs/[orgId]` now renders a role `<select>` and a Remove/Leave button
  per member row (gated the same way the existing invite UI is: admin
  affordances only render for `team_owner`/`org_admin`, with a
  self-leave affordance additionally available to any member on their own
  row), with the server error message (e.g. "cannot remove the last team
  owner") surfaced inline rather than silently failing.
