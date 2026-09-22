# ADR 0010: Organization invitations use a manually-shared link, not email delivery

## Status

Accepted.

## Context

`organizations`/`organization_members`/`organization_invitations` (and their
RLS policies, including the `token_hash`-only storage design) were built in
`20260921000003_organizations_teams.sql` and
`20260921000005_identity_rls_policies.sql`, but the invitation lifecycle
itself — generating a token, redeeming it, and getting it in front of the
invitee — was never implemented. This app has no transactional email
provider configured or wired up anywhere (auth emails like signup
confirmation and password reset are handled entirely by Supabase Auth
itself, not by this app's own code), and standing one up requires an
external account only the human owner can create — the same category of
external dependency deferred for live billing in ADR 0005.

## Decision

- `create_organization_invitation(org_id, email, role)` is a
  `SECURITY DEFINER` function that independently re-checks the caller is an
  org admin/team owner (RLS is bypassed inside a `SECURITY DEFINER` function,
  so this check cannot be skipped), generates a random 256-bit token via
  `pgcrypto`'s `gen_random_bytes(32)`, stores only its sha256 hash
  (`token_hash`, exactly as the column comment already documented), and
  returns the **raw token to the caller, exactly once**.
- The admin UI (`/orgs/[orgId]`) displays that raw token as a full
  `/invite/<token>` link immediately after creation, with an explicit copy
  button and a note that it will never be shown again. The admin is
  responsible for sending it to the invitee themselves (email, Slack,
  whatever channel they already use) — there is no "Send" button that
  pretends an email went out.
- `accept_organization_invitation(token)` hashes the presented token and
  looks it up by `token_hash` (there is deliberately no "select invitation
  by token" RLS policy — see the comment on
  `org_invitations_select_org_admin` — token verification only ever happens
  through this function). It independently re-verifies: not revoked, not
  already accepted, not expired, and that the accepting account's email
  matches the invited email, before inserting into `organization_members`.
- `/invite/[token]` is a standalone route **outside** the `(app)` route
  group specifically so it is not wrapped by the app layout's unconditional
  `requireUser()` redirect (which drops any `?next=` context) — an
  unauthenticated visitor is instead redirected to
  `/login?next=/invite/<token>`, so they land back on the invite page right
  after logging in or signing up.
- `organizations.seat_limit` (a column that already existed but was never
  enforced anywhere) is now genuinely enforced inside
  `create_organization_invitation()`: existing members plus other
  outstanding (unexpired, unrevoked, unaccepted) invitations count against
  it.

## Why

This mirrors the same honesty principle as ADR 0005: build the real
data model and real server-side enforcement now, and be explicit in the UI
about the one piece that genuinely requires an external service this build
environment cannot provision. A fake "invitation sent!" toast with no actual
delivery would be strictly worse than an honest "here is the link, share it
yourself" — the latter is fully functional today, just manual.

## Consequences

- Connecting a real transactional email provider later is additive: call
  the same `create_organization_invitation()` RPC, then hand its returned
  token to the email provider's send call instead of (or in addition to)
  displaying it in the UI. No schema or RLS change is needed.
- Until then, org admins must share invite links out-of-band. This is
  documented in `RELEASE_CHECKLIST.md`, not hidden.
- `supabase/tests/013_org_instructor_visibility_and_invitations.sql` proves:
  happy-path accept, a token cannot be redeemed twice, an invitation cannot
  be accepted by an account with a different email, expired/revoked
  invitations are rejected, `seat_limit` is genuinely enforced, and only an
  org admin/team owner can create an invitation.
