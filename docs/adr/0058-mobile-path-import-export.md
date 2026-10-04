# ADR 0058: Path import/export on mobile -- closing the last admin gap

## Status

Accepted.

## Context

The last named mobile `/admin/*` gap: the JSON bundle import/export flow
at `/admin/paths/import` and `/admin/paths/[pathId]/export`. Unlike every
other admin pillar ported this session, neither side is plain RLS-scoped
CRUD:

- **Import** (`admin/paths/import/actions.ts`'s `importPathBundleAction`)
  is a multi-step, hand-rolled-transaction orchestration: insert the path,
  then each module, then each lesson, then its quiz/questions/choices,
  resolving skill slugs along the way, and if anything fails partway
  through, deleting the path row to cascade-clean up everything already
  inserted under it. A Server Action can't be called directly by a
  non-Next HTTP client (Flutter has no way to invoke Next.js's internal
  Server Action protocol), so mobile needs a real Route Handler here --
  and that orchestration is real, non-trivial business logic that must
  not be hand-ported a second time in Dart, where it could drift from the
  original (the same reasoning ADR 0057 used for environment-spec
  validation, ADR 0058's closest precedent).
- **Export** (`[pathId]/export/route.ts`) was already a Route Handler,
  just gated by `requireAdmin()` (cookie-only). Swapping it for
  `requireApiUser()` alone turned out not to be enough: `/admin` is one of
  `lib/supabase/middleware.ts`'s (really `src/proxy.ts`'s)
  `PROTECTED_PREFIXES`, which redirects an unauthenticated *browser*
  request to `/login` before any Route Handler under that prefix ever
  runs -- using only the cookie session, with no knowledge of a Bearer
  header at all. A mobile caller with no cookie would always be redirected
  to an HTML login page, never reaching `requireApiUser()`'s own 401. This
  was caught by the new e2e test itself failing (200 instead of 401)
  before ever reaching mobile -- the fix was moving the route from
  `/admin/paths/[pathId]/export` to `/api/admin/paths/[pathId]/export`
  (not in that prefix list, like every other mobile-facing Route Handler
  in this app) and updating the web admin UI's own "Export" link to the
  new URL. A logged-in admin's browser still works identically either way,
  via the same cookie session.

## Decision

- `apps/web/src/lib/content-io/import-path-bundle.ts` (new): extracted
  `importPathBundle(supabase, adminId, raw)` -- the exact orchestration
  that used to live inline in `importPathBundleAction`, now the single
  shared implementation both the web action and the new mobile route call.
- `admin/paths/import/actions.ts`: `importPathBundleAction` is now a thin
  FormData adapter around `importPathBundle()`.
- `apps/web/src/app/api/admin/paths/import/route.ts` (new): `POST`,
  Bearer-authed via `requireApiUser`, a JSON adapter (`{ bundle: string }`)
  around the same `importPathBundle()`.
- `apps/web/src/app/api/admin/paths/[pathId]/export/route.ts` (moved from
  `(app)/admin/paths/[pathId]/export/route.ts`): same logic, now
  `requireApiUser()`-gated and reachable by Bearer token from mobile.
- `admin/paths/[pathId]/page.tsx`: "Export" link updated to the new URL.
- `apps/web/e2e/smoke.spec.ts`: two more 401-proof tests (36 e2e tests
  total) -- the export one is what caught the `PROTECTED_PREFIXES` bug
  before it ever reached mobile.
- `mobile/app/lib/admin/admin_paths_screen.dart`: an "Export" button on
  `AdminPathDetailScreen`'s app bar (GETs the route, shows the bundle JSON
  in a copy-to-clipboard dialog -- same pattern as the Organizations
  screen's invite link, no new file-storage dependency) and an "Import a
  path" button on `AdminPathsScreen`'s app bar opening a new
  `AdminImportPathScreen` (paste JSON, POST, show the imported slug plus
  any skill-slug warnings). Both shown only when `AppEnv.isApiConfigured`.

## Why

Extracting `importPathBundle()` rather than writing an equivalent Dart
version means the two clients can never disagree about how an import
behaves or what "rolled back" means -- the same single-source-of-truth
reasoning as `environmentSpecSchema` in ADR 0057, just for an
orchestration instead of a schema.

## Consequences

- No new `flutter test`s (188 total, unchanged) -- this phase is UI
  wiring to existing/new Route Handlers, no new pure logic worth testing
  beyond what `path-bundle.test.ts` already covers on the web side.
- +2 e2e tests (36 total, was 34). `tsc --noEmit`, ESLint, `npx vitest
  run` (316 tests, unchanged), and `npm run build` all pass; the fix for
  the `PROTECTED_PREFIXES` redirect bug was verified by the same e2e test
  that first caught it.
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL`.
- Closes every mobile `/admin/*` gap this app has named since ADR 0026.
  The only mobile gap left anywhere is Mentor's context-specific deep
  links (ADR 0034).
