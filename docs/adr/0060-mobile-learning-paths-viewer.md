# ADR 0060: Learner-facing Learning Paths viewer on mobile

## Status

Accepted.

## Context

ADR 0059 named the one gap it deliberately did not close: mobile has no
way to actually read a lesson. `admin_paths_screen.dart` (ADR 0055) only
ever built the staff authoring side -- creating/editing paths, modules,
and lessons -- mirroring `apps/web/src/app/(app)/admin/paths/**`. The
learner-facing side, `apps/web/src/app/(app)/learn/**` (`learn/page.tsx`,
`learn/[pathId]/page.tsx`, `learn/[pathId]/[moduleId]/[lessonId]/page.tsx`,
`mark-read.tsx`, `quiz-attempt.tsx`), had no mobile counterpart at all,
which is also why the Mentor `lesson` context deep link (ADR 0059) had
nowhere to attach.

Reading those four web files confirmed this needs zero new Route
Handlers: `learning_paths`/`modules`/`lessons` are staff-write/
anyone-reads-published via RLS, same as every other content table this
session has ported; `lesson_progress` is owner-read-write-own
(`lesson_progress_own`); and grading runs through the same real
`submit_quiz_attempt()` RPC every other quiz surface in this app already
calls (Exams, the admin quiz preview). `quiz-attempt.tsx`'s own payload
construction only ever sends a single-element answer list per question,
even for a `multi_choice` question -- not something to "fix" on mobile,
since the web lesson page has the identical limitation; `lesson.dart`
documents this explicitly next to `buildLessonQuizAnswerPayload`.
`[lessonId]/page.tsx`'s own grouping of `quiz_questions_for_attempt`'s
rows also never re-sorts by `order_index` the way the dedicated Exams
flow's grouping does, so `groupLessonQuizRows` doesn't either.

A genuinely new question this phase had to answer: how to render
`lessons.content_markdown`. Grepping every other `*_markdown` field in
this app (org announcement bodies, report content, the admin lesson
editor's own textarea, and -- confirmed by reading
`dashboard_screen.dart` -- the learner-facing dashboard's own active-
announcement display) showed none of them render Markdown; all show the
raw string in a plain `Text`. No markdown-rendering package exists
anywhere in this app's `pubspec.yaml`. Rendering lesson content as plain
text keeps this screen consistent with that existing app-wide convention
rather than introducing the app's first markdown-rendering dependency for
one screen while every other Markdown field stays unrendered.

## Decision

- `lib/learn/lesson.dart` (new): pure models/helpers mirroring the web
  source exactly -- `LearningPathSummary`, `LessonSummary`,
  `groupLessonsByModule()`, `LessonDetail`, `LessonQuizChoice`,
  `LessonQuizQuestion`, `LessonQuiz`, `groupLessonQuizRows()`,
  `buildLessonQuizAnswerPayload()`.
- `lib/learn/learn_screen.dart` (new): `fetchLearningPaths()` (published
  paths, ordered); `LearnPathsListScreen` (path list); `LearnPathDetailScreen`
  (modules grouped with their published lessons, each lesson row showing
  "Read" once `lesson_progress.completed_at` is set or the estimated
  minutes otherwise); `LessonViewerScreen` (lesson content, a "Mentor"
  button with `contextType: 'lesson'` finally giving ADR 0059's deep link
  somewhere to attach, an on-load `lesson_progress` upsert mirroring
  `mark-read.tsx`'s own "once per mount" guard via a `_marked` bool field,
  and -- when a published quiz is linked via `quizzes.lesson_id` -- an
  embedded pass/fail quiz form calling `submit_quiz_attempt()` the same
  way `lib/exams/exam_attempt.dart` already does).
- `lib/home/more_screen.dart`: added a "Learn" entry to `_baseItems`,
  between Investigate and Exams.

## Why

`lesson_progress_own` RLS is the real completion-tracking boundary
either way, so the client-side `_marked` guard in `_markRead()` is only
there to avoid a redundant upsert per rebuild -- same role as
`mark-read.tsx`'s `useRef` on web, not a security control.

## Consequences

- +6 `flutter test`s (`lesson_test.dart`: `groupLessonsByModule`,
  `groupLessonQuizRows`, `buildLessonQuizAnswerPayload`) -- 200
  `flutter test`s total (was 194).
- `flutter analyze` stays clean (the two `RadioListTile`
  `deprecated_member_use` infos on the quiz choices match the same,
  pre-existing pattern already in `lib/exams/exam_attempt.dart`, not a
  new issue). `flutter build web` succeeds both with and without
  `API_BASE_URL` (no new Route Handler, so neither config changes this
  phase's behavior).
- Closes the last named mobile gap from ADR 0059: the Mentor `lesson`
  context deep link now has a real screen to open from. The only
  remaining named Mentor gap anywhere is conversation-resume-on-reopen,
  a pre-existing limitation on every context, not new here.
