# ADR 0057: Terminal environment editor on mobile (Route Handler + screen)

## Status

Accepted.

## Context

ADR 0056 named the terminal environment spec editor as the one piece of
the Labs admin page deliberately not ported: `environment-manager.tsx`'s
web Server Action (`saveEnvironmentAction`) validates the submitted JSON
against `lib/terminal/spec.ts`'s `environmentSpecSchema` -- the same
schema `lib/terminal/execute.ts` parses an environment with -- before
ever saving it, and the database's own `lab_environments_spec_is_object`
constraint only checks the column is a JSON object, not its actual shape.
A plain Postgrest upsert from mobile would skip that validation and could
save a spec that silently breaks a learner's terminal.

Closing that gap safely needs the validation to run in exactly one place,
not reimplemented in Dart where it could drift from the TypeScript
original. The new `/api/admin/labs/{labId}/environments` Route Handler
does exactly that: `requireApiUser()` resolves who's calling (same
Bearer-token pattern as every other mobile-facing Route Handler in this
app), then the handler itself calls `environmentSpecSchema.safeParse()`
before upserting through that caller's own RLS-scoped Supabase client --
`lab_environments_staff_only` (`FOR ALL`) is still the real authorization
boundary, exactly as it would be for a direct Postgrest write; the route
adds schema validation, not a new permission check. Listing, loading into
the editor, and deleting an environment need no such validation, so they
stay plain Postgrest calls from the mobile screen and never touch this
route.

## Decision

- `apps/web/src/app/api/admin/labs/[labId]/environments/route.ts` (new):
  `POST` accepts `{ variant_seed, spec_json }` (the same shape the web
  form submits), re-parses `spec_json` with `JSON.parse`, validates the
  result with `environmentSpecSchema`, and upserts
  `{ lab_id, variant_seed, spec }` onto `lab_environments` with
  `onConflict: "lab_id,variant_seed"` -- mirroring
  `saveEnvironmentAction` field-for-field, including its exact "Spec
  failed validation: ... (at ...)" error message shape.
- `apps/web/e2e/smoke.spec.ts`: a 7th 401-proof test (34 e2e tests
  total).
- `mobile/app/lib/admin/admin_lab.dart`: `AdminLabEnvironment` row
  parser, `prettyPrintJson()` (mirrors `JSON.stringify(v, null, 2)`), and
  `placeholderEnvironmentSpecJson` (the exact same `PLACEHOLDER_SPEC` the
  web editor seeds itself with, Cyber Range fields included).
- `mobile/app/lib/admin/admin_labs_screen.dart`: `AdminLabDetailScreen`
  gained an "Environments" section -- a list of existing environments
  (plain Postgrest `select`/`delete`, each with "Load into editor" and
  Remove), a variant-seed field, and a JSON spec textarea with a "Save
  environment" button that POSTs to the new route with the session's
  Bearer token. Shown (for saving) only when `AppEnv.isApiConfigured`,
  same convention as Mentor/Scanner/the lab terminal; listing and
  deleting still work without it.

## Why

Reusing `environmentSpecSchema` itself, rather than hand-porting an
equivalent validator to Dart, is the only way to guarantee the web and
mobile admin clients can never disagree about what a valid spec is --
exactly the scenario ADR 0056 flagged as the real risk of skipping this
work rather than deferring it.

## Consequences

- +3 `flutter test`s (`AdminLabEnvironment.fromRow`, `prettyPrintJson`,
  `placeholderEnvironmentSpecJson`'s shape) -- 188 `flutter test`s total
  (was 185).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (the new section degrades to view/delete-only
  without it, same as every other Route-Handler-backed mobile screen).
- `tsc --noEmit`, ESLint, `npx vitest run` (316 tests, unchanged -- the
  route has no new pure logic of its own to unit-test beyond the already
  -tested `environmentSpecSchema`), `npm run build`, and the extended e2e
  suite all pass.
- Closes the Labs admin gap entirely. The only remaining mobile `/admin/*`
  gap is path import/export.
