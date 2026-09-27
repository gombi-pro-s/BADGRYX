# ADR 0033: Bearer-token auth for Route Handlers a mobile client calls directly

## Status

Accepted.

## Context

`/api/mentor/chat` (the AI Mentor's only entry point) authenticated
callers with `requireUser()` (`lib/auth/session.ts`), which reads the
Supabase session from browser cookies and calls Next's `redirect("/login")`
if none is found. That's correct for `apps/web`'s own Server
Components/pages, but wrong for a bare HTTP client: a mobile app has no
cookie jar and can't follow a redirect into anything meaningful -- it
needs a real `401` it can branch on.

The Flutter app (via `supabase_flutter`) already holds a JWT
(`session.accessToken`) after login. The natural transport for it to a
Next.js Route Handler is a standard `Authorization: Bearer <token>`
header. The question was how to turn that header into the same kind of
RLS-scoped Supabase client `apps/web` already uses server-side, without
touching `service_role` and without changing any behavior for existing
web callers (who never send that header).

Rather than guess at `@supabase/ssr`/`@supabase/supabase-js` behavior,
the actual installed package source was read directly:
`node_modules/@supabase/supabase-js`'s `SupabaseClient` constructor merges
`global.headers` into every sub-client it creates, including the auth
(`GoTrueClient`) sub-client; `node_modules/@supabase/auth-js`'s
`GoTrueClient._getUser(jwt)` shows that passing a JWT explicitly is the
simplest, most robust verification path -- it calls `/user` with exactly
that token, independent of any stored session or custom-header
propagation.

## Decision

- `lib/auth/bearer.ts`: pure `extractBearerToken(authorizationHeader)`
  parses `Authorization: Bearer <token>` (case-insensitive scheme, tolerant
  of surrounding whitespace); returns `null` for anything else. Unit
  tested directly, 7 cases.
- `lib/supabase/route-handler.ts`: `createRouteHandlerClient(bearerToken?)`
  mirrors `lib/supabase/server.ts`'s existing `createClient()` (same
  cookie handling, same anon key) exactly, adding only a conditional
  `global: { headers: { Authorization: `Bearer ${bearerToken}` } }` when a
  token is passed -- so every subsequent Postgrest/RPC call this client
  instance makes carries that JWT, and RLS's `auth.uid()` resolves to that
  token's user.
- `lib/auth/api.ts`: `requireApiUser(request)` -- the Route Handler
  equivalent of `requireUser()`. Extracts a bearer token if present;
  verifies with the explicit `supabase.auth.getUser(token)` form when one
  exists (falls back to the existing cookie-based `supabase.auth.getUser()`
  otherwise); returns `{ unauthorized: NextResponse }` (a real `401` JSON
  body) instead of redirecting, or `{ user, supabase }` on success.
- `/api/mentor/chat` now calls `requireApiUser(request)` in place of
  `requireUser()` + `createClient()`. Every other line (quota check,
  conversation resolution, history fetch, context building, NDJSON
  streaming, message persistence, audit log) is unchanged.

## Why

- **Zero behavior change for the web app.** `apps/web`'s own `fetch()`
  calls never send a custom `Authorization` header, so `requireApiUser()`
  falls straight through to the same cookie-session path `requireUser()`
  already used. Verified, not assumed: this mirrors `lib/supabase/server.ts`
  line for line, and the new e2e tests below confirm a request with no
  bearer token and no cookie still gets a clean `401`, not a crash or an
  accidental redirect.
- **No new trust boundary.** The returned client is always anon-key +
  a real user JWT (either the cookie session's or the bearer token's) --
  never `service_role`. RLS is the only enforcement boundary either caller
  gets, identical to every other client in this app.
- **Verified against real SDK source, not documentation guesswork**, given
  this touches shared auth code: read `@supabase/supabase-js`'s header
  merging and `@supabase/auth-js`'s `_getUser(jwt)` conditional logic
  directly before writing `requireApiUser()`.

## Consequences

- +7 unit tests (`bearer.test.ts`) -- 308 unit tests total (was 301).
- +2 e2e tests (`smoke.spec.ts`, "mobile API auth"): an unauthenticated
  call to `/api/mentor/chat` gets a `401` JSON body (not a redirect); a
  bogus `Bearer` token is rejected the same way rather than throwing --
  29 e2e tests total (was 27).
- `tsc --noEmit`, ESLint, and `next build` all stay clean.
- This is the auth foundation task #141 (the Flutter Mentor chat screen)
  builds on; no other Route Handler was changed, so no other endpoint yet
  accepts a bearer token.
