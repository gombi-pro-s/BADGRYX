# ADR 0054: Admin Quizzes screen on mobile

## Status

Accepted.

## Context

Next in the remaining `/admin/*` list (learning paths, labs, quizzes, path
import/export) after CTF Challenges/Events (ADR 0053): Quizzes. Reading
`20260921000009_content_model_rls.sql` confirmed the same shape again --
`quizzes`/`quiz_skills` are staff-write/anyone-read, and
`quiz_questions`/`quiz_choices` are staff-only full stop (learners read
`quiz_questions_for_attempt` instead, a separate view that never exposes
`is_correct`). All plain RLS-scoped Postgrest CRUD, no Route Handler.

One real asymmetry from CTF Challenges/Events: the web admin UI has no
"edit quiz" form at all. Once a quiz is created, its own fields (slug,
title, passing score, time limit, hint policy, exam flag) are fixed --
`[quizId]/page.tsx` only ever renders a publish toggle, the skill tagger,
and the questions manager, never a form to change those fields. Mobile
doesn't invent an edit form the web doesn't have either.

`questions-manager.tsx` only ever creates `single_choice` questions (the
type is hardcoded in its one call to `createQuestionAction`), starts with
exactly two blank choices, and validates (after trimming and dropping
empty choices) that at least two remain and at least one is marked
correct -- ported as pure `trimmedNonEmptyChoices()`/`quizChoicesError()`.

## Decision

- `lib/admin/admin_quiz.dart` (new): `quizHintPolicies`, `isValidQuizSlug()`,
  `AdminQuiz`/`AdminQuizQuestion`/`AdminQuizChoice` row parsers,
  `QuizChoiceDraft`, `trimmedNonEmptyChoices()`, `quizChoicesError()`.
- `lib/admin/admin_quizzes_screen.dart` (new): `AdminQuizzesScreen` (list +
  FAB), `AdminCreateQuizScreen` (create-only -- no edit form, matching the
  web), and `AdminQuizDetailScreen` (publish toggle with the same
  `log_audit_event` call `toggleQuizPublishedAction` makes, an inline skill
  tagger identical in shape to the CTF Challenges one, and a questions
  manager: existing questions with their choices and a Remove button, plus
  an add-question form with a dynamic, growable choice list).
- `lib/admin/admin_screen.dart` gained a "Quizzes" entry.

## Why

Keeping this screen's shape exactly as narrow as the web's -- no quiz-field
editing, single_choice-only question creation -- means mobile never
implies a capability the web admin itself doesn't have, consistent with
this session's rule against adding anything beyond what was asked.

## Consequences

- +8 `flutter test`s (`isValidQuizSlug`, both row parsers,
  `trimmedNonEmptyChoices`, `quizChoicesError`'s three cases) -- 174
  `flutter test`s total (was 166).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Narrows the remaining `/admin/*` mobile gap to learning paths, labs, and
  path import/export.
