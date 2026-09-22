# ADR 0009: The lab terminal's environment spec is interpreted entirely server-side; the client only ever receives command output

## Status

Accepted.

## Context

Section 15/16 call for an interactive terminal simulator against a lab's
virtual environment. A lab's environment necessarily contains its flag
content somewhere reachable by legitimate commands (e.g. `cat flag.txt`).
`labs.environment_spec` (a jsonb column added in
`20260921000008_content_model.sql` as a placeholder, never actually used)
would, if populated and read the way `labs.title`/`labs.description` are,
be readable by any authenticated session that selects it -- Postgres RLS is
row-level, not column-level, so a published lab's row being visible at all
means every column on it is visible to whatever query asks for it. Running
a client-side JS interpreter against a fetched copy of that spec would mean
the flag ships to the browser in a network response the moment the lab
loads, fully defeating the exercise regardless of what the UI chooses to
display.

## Decision

- **`environment_spec` is dropped from `labs`** and replaced with a
  dedicated `lab_environments` table
  (`20260922000005_lab_terminal.sql`), RLS-locked exactly like
  `lab_flags`: `FOR ALL TO authenticated USING (is_staff())` -- there is no
  policy under which a non-staff session can select it, full stop. This is
  the same pattern AUDIT-006 already established for `ctf_challenges.flag_hash`
  and `lab_flags`: a genuinely secret column lives in its own RLS-locked
  table, not a broadly-readable one.
- **The command interpreter itself is a pure TypeScript function**
  (`lib/terminal/interpreter.ts`, no I/O), but it is only ever *called* from
  `lib/terminal/execute.ts`, a `server-only` module that:
  1. First reads the caller's `lab_instances` row through the caller's own
     RLS-scoped session (`lib/supabase/server.ts`'s `createClient()`) --
     this independently proves the requesting user owns a `running`
     instance of this lab, using the same RLS the rest of the app relies
     on, not a bypass.
  2. Only *then* uses `createAdminClient()` (service_role, bypasses RLS) to
     read `lab_environments.spec` for that lab/variant -- the doc comment
     on `lib/supabase/admin.ts` already states exactly this precondition
     ("code that has already independently verified the caller's authority
     to perform the operation"); this is that precondition satisfied, not
     assumed.
  3. Runs the pure interpreter against the spec and the instance's current
     `environment_state`, producing one command's output.
  4. Persists the updated `environment_state` and an append-only
     `lab_terminal_commands` row through the caller's own session again
     (ordinary owner-scoped RLS, no escalation needed for a write the user
     is already allowed to make).
  5. Returns only that one command's rendered output string to the caller
     -- never the spec, never any other file's content the command didn't
     touch.
- **`POST /api/labs/[labInstanceId]/terminal`** is the only entry point;
  there is no Supabase table/RPC grant that would let a client read
  `lab_environments` directly or run the interpreter itself, so this
  boundary is structural, not just "the UI doesn't show it."
- **The transcript (`lab_terminal_commands`) carries no grading weight by
  itself.** A user must still separately call the existing
  `submit_lab_flag()` (ADR 0003) with the flag text they found -- the
  terminal is an interaction surface, not a new write path into the
  Skill Graph.

## Why

This is the same principle ADR 0007 (AI Mentor) and ADR 0008 (scanner
findings) apply in their own domains, here applied to "the content that
proves you solved the lab": a secret must never leave the server except as
the specific, minimal, already-authorized answer to a specific request --
never as raw source data a sufficiently curious client could inspect
directly. `lab_flags` already established the pattern (a hash, verified
only inside a `SECURITY DEFINER` function); this reuses it for a richer
secret (a whole filesystem tree) via `service_role` plus an independent
ownership check, since a filesystem tree isn't something a single SQL
function can usefully interpret the way a flag-hash comparison is.

## Consequences

- Any new command added to the interpreter must be added to
  `lib/terminal/interpreter.ts`, kept pure and unit-tested there (see
  `lib/mentor/prompt.ts`'s precedent for why: no database or network call
  needed to test it exhaustively).
- Nothing may read `lab_environments` from a user-session Supabase client,
  ever -- if a future feature needs to show a *hint* about the environment
  (e.g. "here's the file listing of /home/user"), that must be a new,
  narrowly-scoped server-side function, not broader read access to the
  table itself.
- `supabase/tests/009_lab_terminal_rls.sql` is the executable proof that
  `lab_environments` is unreadable by a non-staff session -- if a future
  migration ever adds a SELECT policy for `authenticated` on that table,
  this test fails immediately.
