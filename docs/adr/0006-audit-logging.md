# ADR 0006: Append-only audit log, written only through one function

## Status

Accepted.

## Context

Section 34 requires an auditable log of security-relevant events (login,
role change, admin action, scan started/completed, billing entitlement
changed, etc.) without logging sensitive content (passwords, tokens, API
keys, flags, full request bodies).

## Decision

- `audit_log` is append-only: no UPDATE or DELETE grant exists for any
  non-service role, enforced by RLS having no matching policy for those
  operations (combined with `FORCE ROW LEVEL SECURITY`).
- The only way to write a row is `public.log_audit_event(action,
  target_type, target_id, organization_id, metadata)`, a `SECURITY DEFINER`
  function that stamps `actor_id`/`actor_role` from the current session
  itself (`auth.uid()`/`auth.role()`) — a caller cannot forge who performed
  an action or backdate an entry, because it never accepts those as
  parameters.
- Readable by platform admins (all rows) or an organization's own
  `org_admin`/`team_owner` (rows scoped to their `organization_id`).

## Why

An audit log a privileged user can edit or delete is not an audit log. Even
admins get read-only access in this design (see the explicit regression
test asserting this in `supabase/tests/001_identity_rls.sql`). Centralizing
writes through one function means every audit event has a consistent,
trustworthy `actor_id`, instead of application code passing an
easily-wrong or spoofable actor id per call site.

## Consequences

- Every new security-relevant action (scan started, finding changed, report
  generated, etc., per the section 34 list) should call
  `log_audit_event()`, not insert into `audit_log` directly (which is
  blocked by RLS anyway) and not build a parallel logging table.
- Callers must never pass secrets, tokens, passwords, or full flag values
  into `metadata` — this is a code-review rule, not something the schema
  can enforce structurally, since `metadata` is intentionally a flexible
  `jsonb` column.
