# ADR 0016: Bulk import/export of content — learning paths only, scoped by real FK structure

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` flagged "bulk import/export of content" as unbuilt.
The content model (ADR 0004) has several standalone content types — learning
paths, labs, CTF challenges, capstones — but only `learning_paths → modules →
lessons → quizzes → quiz_questions → quiz_choices` is a real FK-linked
hierarchy. Labs and CTF challenges are only *informally* associated with a
path, through the shared `skills` table (a lesson and a lab can share a
`skill_id` tag) — there is no `path_id` column on `labs` or
`ctf_challenges`, and no admin UI convention that treats a lab as "belonging"
to a path.

Labs and CTF challenges also each store a `flag_hash`, never a plaintext
flag (`lib/security/flag-hash.ts`'s `hashFlag()` is a one-way SHA-256; the
plaintext is never persisted anywhere). An "export" of a lab or CTF
challenge could therefore only ever emit a hash that's useless for
recreating working content in a different environment — re-importing it
would either silently produce a lab with an unverifiable flag, or the
importer would have to invent a "please re-enter the flag" step that turns
what should be one bulk operation into N manual ones.

## Decision

Scope this to **learning paths only** — the one content type with a real,
traversable FK hierarchy and no secret-material problem:

- A new JSON format, `icorepen.learning_path.v1`
  (`lib/content-io/path-bundle.ts`), describes a path with its modules,
  lessons, each lesson's skill tags (by **slug**, not id — ids don't survive
  a move between environments), and each lesson's optional quiz with its
  questions and choices.
- `pathBundleSchema` (zod) and `parsePathBundle(raw): {data, error}` are
  pure — no Supabase client, no I/O — and are unit-tested directly (9
  tests), matching this codebase's established "pure logic vs server-only
  I/O" split (`lib/mentor/prompt.ts`, `lib/turnstile/turnstile.ts`).
- **Export**: `GET /admin/paths/[pathId]/export` (a Route Handler, not a
  Server Action, so a plain link can trigger a file download) walks the
  hierarchy and serializes it, resolving skill ids to slugs. Ordering is
  expressed purely by array position in the JSON — nothing in the admin UI
  actually sets `order_index` today (every create action lets it default to
  0), so re-deriving it from array order on import is simpler and no less
  correct than round-tripping a numeric column nothing else populates.
- **Import**: `importPathBundleAction`
  (`admin/paths/import/actions.ts`) always creates a **new** path — it never
  merges into or overwrites an existing one. It resolves every skill slug
  referenced in the bundle to this environment's skill ids up front, in one
  query; a slug that doesn't exist here is skipped (recorded as a warning),
  not fatal — imported content moved from elsewhere may reference skills
  this environment hasn't created yet, and refusing the whole import over
  one missing tag would be worse than importing without it.

## Why

The alternative — inventing a "this lab belongs to this path" convention
(e.g. "any lab sharing a skill tag with a lesson in this path") — would be a
new modeling decision smuggled into an export feature, not a description of
what the schema already means. Scoping to what the FKs actually express
keeps the feature honest about what "export a path" means today, and leaves
room for a labs/CTF export to be designed on its own terms later (which
would have to solve the flag-secrecy problem, not just the association
problem).

## Consequences

- No SQL migration, no SQL regression test — this phase only reads/writes
  through the same tables and RLS policies the existing admin CMS actions
  already use (plain `is_staff()`-gated RLS, not a SECURITY DEFINER
  function — see ADR 0004; content authoring was never on that path). Like
  ADR 0015 (MFA), this is called out explicitly rather than letting "0 new
  SQL assertions" look like an oversight.
- There's no multi-statement transaction across these PostgREST calls, so
  import failure part-way through is handled by explicit compensation: if
  anything after the initial `learning_paths` insert fails, the action
  deletes that path row, which cascades through every module/lesson/quiz/
  question/choice already created under it (every FK in this hierarchy is
  `ON DELETE CASCADE`). The admin never has to manually clean up a
  half-imported path.
- Verified by 9 unit tests on the pure schema/parser, `tsc --noEmit`, ESLint,
  a clean production build (both new routes present), and one new e2e test
  confirming `/admin/paths/import` sits behind the same auth wall as every
  other admin route. A real authenticated click-through (export a real
  path, import it, confirm the content matches) needs a provisioned
  Supabase project, same limitation as every other admin-CMS flow in this
  sandbox.
