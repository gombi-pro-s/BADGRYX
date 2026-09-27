# ADR 0018: Admin CMS form component tests — mocked-action coverage, not a full RLS round trip

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had flagged admin CMS CRUD flows as "built and
manually verified via typecheck/lint/build only" — no dedicated test
exercises the forms' own behavior (submission wiring, pending state, error
rendering), and the checklist named the reason: a real e2e click-through
needs a live Supabase project (a real Postgres + GoTrue + PostgREST stack)
that this sandbox does not have.

That's still true, and checked directly rather than assumed: this sandbox
has no `supabase` CLI installed, and its Docker daemon isn't reachable
(`docker ps` fails with "no such file or directory" on the daemon socket).
Building a local Supabase-compatible HTTP stub good enough to run this
app's actual `@supabase/ssr` + PostgREST query surface (nested selects,
`.or()`, `.rpc()`, session cookies) would itself be a multi-week project,
and a half-faithful stub would validate against a fake backend, not the
real RLS policies these forms actually depend on — worse than admitting
the gap.

What *is* available, and was completely unused for these forms until now:
this project's existing `vitest` + `@testing-library/react` + `jsdom`
setup, already used for presentational component tests (`EvidenceCell`,
`SeverityBadge`, etc.). A CMS form's own client-side behavior — does
submitting the form call the server action with the right `FormData`, does
the button disable and relabel while pending, does a returned error
actually render — has nothing to do with Postgres or RLS. It's plain React
behavior, testable by mocking the imported "use server" actions module
with `vi.mock()` (a "use server" file has no special meaning outside
Next.js's own compiler — under vitest it's just a plain async function, so
mocking its module is the same as mocking any other import).

## Decision

Add `vi.mock()`-based component tests for a representative slice of admin
CMS forms, establishing the pattern rather than exhaustively covering every
form in one pass:

- `admin/announcements/__tests__/create-announcement-form.test.tsx` (3
  tests) and `edit-announcement-form.test.tsx` (3 tests) — the newest CMS
  surface, covering both the unbound (`useActionState(action, ...)`) and
  id-bound (`useActionState(action.bind(null, id), ...)`) wiring shapes.
- `orgs/[orgId]/announcements/__tests__/create-announcement-form.test.tsx`
  (2 tests) — the double-bound shape (`action.bind(null, organizationId)`),
  proving the pattern also covers a form whose action needs an id supplied
  from the URL params rather than a prop.
- `admin/paths/__tests__/create-path-form.test.tsx` (2 tests) — the
  original, oldest CRUD form in the CMS (predates every phase this session
  has built), proving the approach isn't specific to newly-written code.

Each test renders the real form component, fills real inputs via
`fireEvent`, submits, and asserts against the mocked action: the `FormData`
it received, the bound id argument (where applicable), the pending-state
button label/disabled attribute, and the rendered error text for a
non-null `{error}` return. None of it touches `requireAdmin()`,
`requireOrgInstructor()`, or a real Supabase client — those stay covered
by SQL regression tests against a real local Postgres (`scripts/
run-sql-tests.sh`), which is the actual authority on whether a given role
can write a given row.

## Why

The honest boundary matters more than the coverage number: these tests
prove the forms are wired correctly and behave sensibly under
success/error/pending — they do **not** prove an instructor really can
write their org's announcement and really can't write another org's, which
is what the SQL regression suite already proves independently. Claiming
these component tests as "e2e admin CMS coverage" would overstate what was
verified. They're a real, previously-completely-missing layer of coverage
for a different concern (the form's own client-side correctness), not a
substitute for the RLS-backed integration test the checklist originally
asked for.

## Consequences

- 10 new unit tests (256 total). No SQL, no e2e change — this phase touches
  no schema and no route.
- The remaining admin CMS forms (labs, quizzes/questions, CTF challenges,
  capstones, investigations, users, org member management) are still only
  typecheck/lint/build-verified. The pattern established here is
  mechanical to extend to them; doing so for every form was out of scope
  for one pass and is left as follow-up, listed explicitly in
  `RELEASE_CHECKLIST.md` rather than implied as done.
- A real, RLS-backed, authenticated click-through of any admin CMS flow
  still needs a provisioned Supabase project (`MANUAL_SETUP.md` §2) — this
  ADR does not change that; it narrows what's *left* uncovered to exactly
  that live-integration gap, instead of "everything, including basic form
  wiring."
