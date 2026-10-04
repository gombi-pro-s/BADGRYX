# ADR 0055: Admin Learning Paths screen on mobile (paths/modules/lessons)

## Status

Accepted.

## Context

Next in the remaining `/admin/*` list after Quizzes (ADR 0054): Learning
Paths, the three-level content tree (`learning_paths` → `modules` →
`lessons`) plus `lesson_skills` tagging. Reading
`20260921000009_content_model_rls.sql` confirmed the same shape as every
other admin pillar ported so far: `*_staff_write` policies on all four
tables, anyone reads what's published. Plain RLS-scoped Postgrest CRUD,
no Route Handler.

Two real asymmetries worth naming, both already true of the web admin UI
itself rather than something mobile invents or omits:

- **No module edit form.** `[pathId]/[moduleId]/page.tsx` renders a
  publish toggle and the lesson list/create form, never a form to change
  the module's own title/slug/description after creation -- only a path
  (`EditPathForm`) and a lesson (`EditLessonForm`) get one.
- **No reordering control anywhere.** `order_index` defaults to `0` in
  the schema (`20260921000008_content_model.sql`) and nothing in the web
  admin UI ever sets it to anything else on insert, nor exposes a way to
  change it later. Every new path/module/lesson mobile creates leaves it
  at that same default, matching the web exactly rather than inventing a
  drag-to-reorder control the web doesn't have.

Path import/export (`/admin/paths/import`, `/admin/paths/[pathId]/export`
-- a JSON bundle flow with its own Route Handler on the GET side) is a
separate, still-real gap, intentionally not attempted in this phase: it's
a different shape of work (file upload/download) from the three CRUD
screens here, and deserves its own scoped phase.

## Decision

- `lib/admin/admin_path.dart` (new): `isValidContentSlug()` (one regex,
  shared across all three levels -- the web's own `slugSchema` is shared
  the same way), `AdminLearningPath`, `AdminModuleSummary`,
  `AdminLessonSummary`, `AdminLessonDetail` row parsers.
- `lib/admin/admin_paths_screen.dart` (new):
  - `AdminPathsScreen` (list + FAB) and `AdminCreatePathScreen`
    (create-only).
  - `AdminPathDetailScreen`: an editable title/slug/description form with
    its own Save button (mirroring `EditPathForm`), a publish toggle
    (with the same `log_audit_event` call `togglePathPublishedAction`
    makes), the path's module list, and an inline "New module" form.
  - `AdminModuleDetailScreen`: a publish toggle only (no edit form,
    matching the web), the module's lesson list, and an inline "New
    lesson" form.
  - `AdminLessonDetailScreen`: an editable title/slug/summary/content/
    minutes form with Save, a publish toggle, and an inline skill tagger
    (`lesson_skills`, identical in shape to the Quizzes/CTF Challenges
    ones) with the same "feeds the Skill Graph" note the web page shows.
- `lib/admin/admin_screen.dart` gained a "Learning Paths" entry.

Each nested detail screen returns a `changed` bool on pop so its parent
list screen (path → modules, module → lessons) reloads -- the same
`PopScope`-plus-bool-result pattern every other combined screen in this
app already uses, now threaded three levels deep.

## Why

Mirroring the web's two real gaps (no module edit form, no reordering)
rather than "improving" on them keeps mobile from implying a capability
the web admin itself doesn't have -- consistent with this session's rule
against adding anything beyond what was asked.

## Consequences

- +6 `flutter test`s (`isValidContentSlug`, all four row parsers) -- 180
  `flutter test`s total (was 174).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Narrows the remaining `/admin/*` mobile gap to labs (environments/
  hints/flags) and path import/export.
