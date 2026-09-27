# ADR 0023: Cyber Range interconnected environments (ssh pivoting)

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had "Cyber Range interconnected environments" as
not started. The terminal engine (ADR 0009) already ran a real, tested
Unix-like command subset against one authored virtual host per lab
instance. A "Cyber Range" — the phrase used across security training
platforms for a networked set of hosts a learner has to move between,
using credentials or access found on one host to reach the next — needs
more than one host and a real way to move between them.

## Decision

- `lib/terminal/spec.ts`: `EnvironmentSpec` gains two fields, both
  defaulted so every one of the four pre-existing single-host lab specs
  (and their tests) keeps working completely unchanged: `reachable_hosts`
  (hostnames this, the entry host, can `ssh` to) and `hosts` (additional
  hosts, keyed by hostname, each with its own `filesystem`/`users`/
  `sudo_rules`/`credentials`/`reachable_hosts`). `resolveHost(spec,
  hostname)` normalizes either the entry host's own top-level fields or
  one of `hosts` into one `ResolvedHost` shape, so every command handler
  works the same regardless of which host is current.
- `TerminalState` gains `host` (which host is current) and `sessionStack`
  (suspended `{host, user, cwd}` sessions to return to). `path.ts`'s
  filesystem functions were retyped from taking the whole `EnvironmentSpec`
  to a narrower `{ filesystem }` shape — structurally satisfied by both an
  `EnvironmentSpec` and a `ResolvedHost`, so every existing call site and
  test needed zero changes.
- Two new commands: `ssh <user>@<hostname> <password>` and `exit`/`logout`.
  `ssh` is gated by two independent checks, both real, neither cosmetic:
  the current host's `reachable_hosts` (network topology — you can't
  teleport to a host nothing on your network path reaches) and a genuine
  credential match on the target host (knowing a hostname isn't enough;
  the learner has to have actually found a working `user`/`password` pair,
  e.g. via `cat`/`grep` on the current host, same "find it, don't get told
  it" shape as every other lab flag). `exit` restores the exact suspended
  session it left, and refuses at the origin host rather than doing
  nothing silently.
- One real seeded lab proves it end to end: **Cyber Range: Lateral
  Movement to the Database Host** — a web app host whose cron config
  leaks a database host's real ssh credential, and a flag that only
  exists on that second host.

## Why

The alternative — a real second container/VM per additional host — is
what "Lab engine runtime for an actual live/networked target" (already
tracked in `RELEASE_CHECKLIST.md` as out of scope, see the Labs/Terminal
section) would require, and is a different, much larger feature: real
network sockets, real process isolation, real per-attempt provisioning
infrastructure. This app's terminal has always been a deterministic
virtual environment, not a provisioned live host — extending it to
multiple *virtual* hosts with real network-topology and credential
enforcement is the honest, in-scope version of "interconnected
environments" that fits what's already built, not a claim of running
real networked infrastructure.

## Consequences

- 17 new unit tests: 13 in `cyber-range.test.ts` (network-topology
  refusal, an unresolvable hostname even if claimed reachable, wrong
  password, right password/wrong user, a successful pivot actually
  changing which filesystem/hostname/user/cwd every command sees, a
  second host's own empty `reachable_hosts` blocking further pivoting,
  `exit` restoring the exact suspended session, `exit` refusing at the
  origin, `logout` as an alias, discovered-files tracking surviving a
  pivot and exit, and the `ssh` usage-error message) plus 4 in
  `seeded-lab-5-cyber-range.test.ts` proving the new seeded lab
  specifically is genuinely solvable (and that the flag is genuinely
  unreachable without pivoting, and that a wrong password is genuinely
  rejected). 291 unit tests total (was 274).
- 79 pre-existing terminal tests pass completely unchanged — the schema
  and `path.ts` changes are purely additive/structural.
- `execute.ts`'s state (de)serialization (`lab_instances.environment_state`)
  now round-trips `host`/`sessionStack` too, and the terminal's returned
  `hostname` reflects whichever host is actually current after a pivot,
  not always the entry host — the terminal UI's prompt
  (`user@hostname:cwd$`) already re-fetches this from the server response
  on every command, so a pivot shows up there with no UI changes needed.
- The admin authoring UI (`/admin/labs/[labId]`'s raw JSON spec editor)
  needed no new form fields — `hosts`/`reachable_hosts`/`credentials` are
  just more properties in the same JSON blob, validated by the same
  `environmentSpecSchema`; the placeholder spec and its help text were
  updated so an author discovers the feature exists.
- No SQL migration changes beyond the one content-seeding migration
  (`20260922000027_seed_cyber_range_lab.sql`) — no new tables, so no new
  SQL regression test, the same pattern as the three earlier seeded
  terminal labs.
