# ADR 0012: Account deletion — ownership cascades, attribution nulls

## Status

Accepted.

## Context

Building a real "delete my account" flow immediately surfaced a genuine,
previously-latent bug: 8 columns across the schema reference `auth.users`
with no `ON DELETE` action at all (`user_roles.granted_by`,
`organizations.created_by`, `organization_members.invited_by`,
`organization_invitations.invited_by`, `audit_log.actor_id`,
`learning_paths.created_by`, `capstone_submissions.reviewer_id`,
`subscriptions.granted_by`). Postgres defaults an unspecified `ON DELETE`
to `NO ACTION`, which means deleting a user who has ever granted a role,
created an organization, invited someone, authored content, reviewed a
capstone, granted a subscription, or simply been logged anywhere in
`audit_log` (which, after ADR 0006's expansion, is now almost any admin or
staff account) would fail outright with a foreign key violation. This
would have shipped invisibly — every prior regression test exercised these
functions without ever deleting the acting user afterward.

## Decision

This schema draws a hard line between two categories of `REFERENCES
auth.users (id)`:

- **Ownership** (`ON DELETE CASCADE`): the row's entire reason to exist is
  that user — `skill_evidence.user_id`, `quiz_attempts.user_id`,
  `scans.user_id`, `profiles.id`, etc. Deleting the user should delete the
  row. This was already correct everywhere it existed in the schema.
- **Attribution** (`ON DELETE SET NULL`): the row exists independently of
  that user — it's a record of something they *did*, not something they
  *are*. An audit log entry, an organization, a role grant, a capstone
  review verdict, a piece of authored content. Deleting the user must
  never delete or block deleting these; it should just null out the
  now-dangling "who did this" reference. All 8 columns above were fixed to
  this (two, `organizations.created_by` and
  `organization_invitations.invited_by`, had to become nullable first —
  neither had any code relying on non-null after insert time).

`ON DELETE SET NULL` was chosen over `ON DELETE CASCADE` specifically
because cascading would be actively wrong for `audit_log`: the entire
point of an audit trail is that it survives the actor. A deleted admin's
role grants, capstone reviews, and organization shouldn't vanish from
history just because they later deleted their own account.

Account deletion itself goes through the GoTrue Admin API
(`supabase.auth.admin.deleteUser()`), not a raw `DELETE FROM auth.users`
— the Admin API is what actually owns Supabase Auth's internal
bookkeeping (sessions, refresh tokens, identities); a raw SQL delete would
bypass it. This is the one place in the app that constructs the
`service_role` admin client for a user-triggered action, and it's narrowly
scoped: called only after `requireUser()` independently establishes who
the caller is, only ever targets that caller's own `user.id` (never a
caller-supplied id), and only after the user has re-typed their own email
as an extra confirmation step — the same "server-side escalation only
after independent ownership verification" pattern as ADR 0009's terminal
execution engine, applied to the single most destructive action in the
app.

Data export (`GET /api/account/export`) explicitly filters every single
query to `user_id = <the caller's own id>`, even on tables where RLS alone
would already permit broader reads (an instructor or admin's session can
see other users' rows on several tables by design). This route's job is
"give the caller their own data," not "give the caller everything their
session happens to be allowed to see" — those are different guarantees,
and conflating them would leak other users' data through what looks like
a personal export.

## Why

A real account-deletion feature is exactly the thing that finds this class
of bug — and finding it now, while building the feature, is much better
than a user (or the human operator, via the Supabase dashboard) hitting a
cryptic FK violation trying to delete an account later. Every future
migration that adds a new "who did X" column referencing `auth.users`
should ask which category it is and set `ON DELETE` explicitly rather than
leaving it to default to `NO ACTION`.

## Consequences

- `supabase/tests/018_account_deletion.sql` proves the fix directly: it
  performs a real `DELETE FROM auth.users` (simulating what the Admin API
  does at the Postgres level) after touching all 8 columns, asserts the
  delete succeeds outright, every historical record survives with its
  attribution nulled, and the deleted user's own owned rows are still
  correctly gone via `CASCADE`.
- A historical record whose only remaining trace of "who" is a now-`NULL`
  column is an accepted, permanent state — there is no separate
  "anonymized user" placeholder row, matching how GDPR-style deletion is
  commonly implemented (the fact of the action persists; the identity
  link to a specific deleted person does not).
- `RELEASE_CHECKLIST.md`'s privacy section is updated to reflect that both
  gaps it previously listed (no delete flow, no data export) are now real
  and tested, not just designed.
