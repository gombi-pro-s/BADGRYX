# ADR 0039: Extend Bearer-token API auth to the lab terminal route

## Status

Accepted.

## Context

The interactive lab terminal (`/api/labs/[labInstanceId]/terminal`) is
the last remaining "not on mobile yet" gap the mobile app's own README
and `RELEASE_CHECKLIST.md` named explicitly (mobile Labs shows an honest
banner instead of a terminal). Reading `lib/terminal/execute.ts` and its
Route Handler showed the entire interpreter (tokenizer, virtual
filesystem, command execution, multi-host ssh/exit pivoting for Cyber
Range labs -- 736 lines across `lib/terminal/`) already runs server-side.
`apps/web`'s own `terminal.tsx` client is a thin wrapper: it POSTs a
command string, gets back `{ output, cwd, user, hostname }`, and renders
a transcript -- there is no interpreter logic to port to Dart at all,
only a thin HTTP client, the same shape as the Mentor and Scanner
screens.

## Decision

`app/api/labs/[labInstanceId]/terminal/route.ts` now calls
`requireApiUser(request)` in place of `requireUser()` + `createClient()`,
identical in shape to the Mentor (ADR 0033) and Scanner (ADR 0035)
routes' own changes. Every other line (param/body validation,
`runTerminalCommand()`, error handling) is unchanged.

## Why

Same reasoning as ADR 0033/0035: zero behavior change for `apps/web`'s
own browser calls, RLS remains the only enforcement boundary, proven with
the same shape of test -- a new e2e case asserting an unauthenticated
`POST /api/labs/{id}/terminal` returns a real `401` JSON body rather than
a redirect.

## Consequences

- +1 e2e test (`smoke.spec.ts`, "mobile API auth") -- 31 e2e tests total
  (was 30). Unit test count unchanged (316) -- no new pure logic, only a
  call-site swap identical in shape to ADR 0033/0035's own.
- `tsc --noEmit`, ESLint, and `next build` all stay clean.
- This is the auth foundation the mobile terminal screen (ADR 0040)
  builds on.
