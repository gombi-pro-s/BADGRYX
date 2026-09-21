# ADR 0001: Supabase (Postgres) over Firebase, Next.js + Flutter split

## Status

Accepted.

## Context

The repository was empty; no existing Firebase/Supabase usage, auth, or
data to preserve. The product spec explicitly allows either Firebase or
Supabase for identity data, RBAC, and structured content (skill graph,
labs, CTF, billing, audit logs).

## Decision

- **Backend**: Supabase, using Postgres as the primary datastore, Row Level
  Security for authorization, and Supabase Auth for identity.
- **Web**: Next.js (App Router, TypeScript).
- **Mobile**: Flutter/Dart (planned), talking to the same Supabase backend
  and future Next.js Route Handlers/Edge Functions.

## Why

The product's core data model (Skill Graph state transitions, lab
instances/flags/hints, CTF scoring with anti-cheat constraints, entitlement
checks, audit logs) is fundamentally relational: it needs multi-table joins,
foreign key integrity, partial unique indexes (e.g. "only one correct CTF
submission per user per challenge"), and transactional multi-row writes
(e.g. grading a quiz: insert an attempt, insert evidence per skill,
recompute state — all atomically). Firestore's document model makes these
patterns significantly more awkward and error-prone than plain SQL with
real constraints.

Row Level Security is also a more auditable authorization primitive for
this system than Firestore security rules: RLS policies are plain SQL,
testable with `psql` directly (no emulator required), and compose cleanly
with `SECURITY DEFINER` functions for the "grading function is the only
writer" pattern used throughout (see ADR 0003).

## Consequences

- All authorization logic must be expressed as RLS policies and
  `SECURITY DEFINER` functions, reviewed with the same rigor as application
  code. See `supabase/tests/` for the regression suite this requires.
- The web and future mobile clients share one backend contract (Postgres
  schema + RPC functions), which is what keeps business logic out of React
  components and reusable by Flutter later (product spec section 38).
- No Docker daemon is available in this build environment, so
  `supabase start` (the full local emulator stack) cannot run here. Instead,
  `scripts/local-test-db.sh` stands up a plain local Postgres with a minimal
  stand-in for the `auth` schema and Supabase's Postgres roles, sufficient
  to apply migrations and exercise RLS for real. This is documented in
  detail in `supabase/tests/bootstrap/0000_auth_stub.sql` and should be
  replaced by real `supabase start` once Docker is available, or used
  alongside it.
