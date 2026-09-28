# ADR 0045: Bearer auth on scan finding enrichment + mobile "Enrich with AI"

## Status

Accepted.

## Context

ADR 0044 closed the manual status-transition half of ADR 0036's Scanner
gap since that action is a plain RPC. "Enrich with AI" is the other half,
and it calls a Route Handler
(`/api/scanner/findings/[findingId]/enrich`) -- until now `requireUser()`-
gated, cookie-session only, exactly the state `/api/mentor/chat`,
`/api/scanner/scan`, and the lab terminal route were in before
ADR 0033/0035/0039 wired `requireApiUser()` into each.

## Decision

- `apps/web/src/app/api/scanner/findings/[findingId]/enrich/route.ts`:
  swapped `requireUser()` + `createClient()` for `requireApiUser(request)`,
  the same pattern as the other three routes -- falls through to the
  existing cookie session for `apps/web`'s own callers, accepts
  `Authorization: Bearer <token>` for the mobile app.
- `e2e/smoke.spec.ts`'s `mobile API auth` block gained a fifth 401-proof
  test for this route (unauthenticated call -> 401 JSON, not a redirect).
- `mobile/app/lib/scanner/scan_detail_screen.dart`: `_FindingCard` now
  tracks its own `explanation`/`impact`/`remediation`/`secureExample`/
  `aiEnriched` as local state (previously read straight from the row) so
  a successful enrich call can update them in place, and gained an
  "Enrich with AI" button next to the status-transition buttons, POSTing
  to the newly-Bearer-authed route with the session's access token --
  same pattern as `new_scan_screen.dart`'s scan submission. The button
  only renders when `AppEnv.isApiConfigured`, so a build without
  `API_BASE_URL` still gets every other Scanner feature (read, status
  transitions) unblocked.

## Why

Enrichment updating local widget state from the RPC/HTTP response rather
than re-fetching the whole scan mirrors `finding-card.tsx`'s own
`setFinding((prev) => ({...prev, ...}))` -- the server's returned row is
the source of truth for what changed, not a client-side guess.

## Consequences

- 32 e2e tests total (was 31); web unit tests, `tsc --noEmit`, ESLint, and
  a production build all stay clean.
- `flutter analyze` stays clean; 116 `flutter test`s still pass (no new
  pure logic here, so no new unit tests); `flutter build web` succeeds
  both with and without `API_BASE_URL`.
- Closes ADR 0036's Scanner gap down to just multi-file upload on the
  "New scan" screen, the one feature left needing a file picker rather
  than a paste box.
