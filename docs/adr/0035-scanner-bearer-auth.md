# ADR 0035: Extend Bearer-token API auth to the scanner's scan-submission route

## Status

Accepted.

## Context

ADR 0033 built `requireApiUser(request)` for one route
(`/api/mentor/chat`). The next mobile pillar is the Security Scanner
(ADR 0036), whose scan submission also runs server-side (the
deterministic rule engine plus persistence, `lib/scanner/orchestrate.ts`)
behind `POST /api/scanner/scan` -- the same "a non-Supabase Route Handler
a mobile client must call directly" shape `/api/mentor/chat` already had.

## Decision

`app/api/scanner/scan/route.ts` now calls `requireApiUser(request)` in
place of `requireUser()` + `createClient()`, identical to the Mentor
route's change: `const auth = await requireApiUser(request); if
("unauthorized" in auth) return auth.unauthorized; const { user, supabase
} = auth;`. Every other line (quota check, `runScan()`, audit log) is
unchanged.

`POST /api/scanner/findings/[findingId]/enrich` is **not** wired yet --
the first mobile Scanner screen (ADR 0036) is read-only for findings (no
enrich-with-AI action), so there is nothing mobile-side calling it. Wiring
it is a one-line change identical to this one whenever a mobile enrich
action is actually built; leaving it on `requireUser()` until then is an
honest reflection of what's actually reachable from mobile today, not an
oversight.

## Why

Same reasoning as ADR 0033: zero behavior change for `apps/web`'s own
browser calls (no `Authorization` header sent -> falls through to the
existing cookie path), RLS remains the only enforcement boundary, and the
change is proven with the same shape of test -- a new e2e case asserting
an unauthenticated `POST /api/scanner/scan` returns a real `401` JSON
body rather than a redirect.

## Consequences

- +1 e2e test (`smoke.spec.ts`, "mobile API auth") -- 30 e2e tests total
  (was 29). Unit test count unchanged (308) -- no new pure logic, only a
  call-site swap identical in shape to the one ADR 0033 already covers
  with its own bearer-parsing unit tests.
- `tsc --noEmit`, ESLint, and `next build` all stay clean.
- The enrich route remains on cookie-only auth until a mobile enrich
  action exists to call it -- tracked, not silently deferred.
