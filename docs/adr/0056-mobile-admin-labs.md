# ADR 0056: Admin Labs screen on mobile (labs/hints/flags)

## Status

Accepted.

## Context

Last of the ascending-complexity admin CRUD pillars after Learning Paths
(ADR 0055): Labs. Reading `20260921000009_content_model_rls.sql` confirmed
the same shape again -- `labs`/`lab_skills`/`lab_hints` are staff-write,
anyone-reads-published (`lab_hints` additionally lets a learner read a
hint they've already unlocked); `lab_flags` is staff-only, full stop, no
one else reads it at all. Plain RLS-scoped Postgrest CRUD, no Route
Handler, for the lab's own fields, its skill tags, its hints, and its
flags (hashed on-device with the same `hashCtfFlag()` ADR 0053 already
built -- `labs`/`ctf_challenges` share the exact `LabCategory`/
`DifficultyLevel` enums too, so this screen imports `ctfCategories`/
`ctfDifficulties` from `admin_ctf.dart` rather than redeclaring identical
lists).

One piece of this admin page is **not** ported here:
`environment-manager.tsx`, the terminal environment's spec JSON editor.
Reading `saveEnvironmentAction` in `actions.ts` showed why it's different
from everything else on this page -- it parses the submitted JSON and
validates it against `lib/terminal/spec.ts`'s `environmentSpecSchema`
*before* the upsert, specifically so "a spec that saves is one that will
actually work" against `lib/terminal/execute.ts`. Checking the database
constraint on `lab_environments.spec`
(`lab_environments_spec_is_object` in `20260922000005_lab_terminal.sql`)
confirmed Postgres only checks it's a JSON *object* -- nothing about its
actual shape. That real schema validation exists exclusively in that one
TypeScript zod schema. A plain Postgrest upsert from mobile would skip it
entirely, which isn't a missing nice-to-have -- it's a real way to ship a
broken terminal to a learner, discovered only when they open it. That
needs a Route Handler that reuses `environmentSpecSchema` itself (so the
two clients can never validate differently), which is real, separate work
and deliberately not attempted in this phase.

## Decision

- `lib/admin/admin_lab.dart` (new): `isValidLabSlug()`, `AdminLab`/
  `AdminLabHint`/`AdminLabFlag` row parsers.
- `lib/admin/admin_labs_screen.dart` (new): `AdminLabsScreen` (list + FAB),
  `AdminCreateLabScreen` (create), and `AdminLabDetailScreen` -- an
  editable title/slug/category/difficulty/minutes/points/description form
  with Save, a publish toggle (same `log_audit_event` call
  `toggleLabPublishedAction` makes), an inline skill tagger
  (`lab_skills`), a hints manager (list sorted by level with Remove, plus
  an add form), a flags manager (list with Remove, plus an add form that
  hashes its plaintext with `hashCtfFlag()` before the insert), and a
  plain-text note that the terminal environment editor isn't here yet and
  to use `apps/web`'s own admin page for that lab until it is.
- `lib/admin/admin_screen.dart` gained a "Labs" entry.

## Why

Reusing `ctfCategories`/`ctfDifficulties`/`hashCtfFlag` from
`admin_ctf.dart` instead of redeclaring them is the first time this
session's admin screens shared pure helpers across files rather than each
duplicating its own copy -- justified here specifically because the two
enums and the hash function are the *same* value by definition
(`LabCategory`/`DifficultyLevel`/`hashFlag()` on the web side), not just
similarly shaped.

## Consequences

- +5 `flutter test`s (`isValidLabSlug`, all three row parsers) -- 185
  `flutter test`s total (was 180).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Closes the Labs CRUD gap; narrows the remaining `/admin/*` mobile gap to
  exactly two items: the terminal environment spec editor (this ADR) and
  path import/export (ADR 0055).
