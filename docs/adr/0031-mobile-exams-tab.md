# ADR 0031: Mobile Exams tab, and a 6-tab bottom nav scaling note

## Status

Accepted.

## Context

After Home/Labs/Investigate/Skills/CTF (ADRs 0026-0030), Exams was the
next tractable pillar: a real countdown timer, single/multi-choice
answers, grading exclusively through `submit_quiz_attempt()` -- a direct
port of `apps/web`'s `/exams` + `exam-attempt.tsx`, including that
component's own honestly-documented limitation (the timer is client-side
only, with no server-side exam-session record, so a refresh restarts the
clock).

## Decision

- `lib/exams/exam.dart`: `Exam`/`ExamQuestion`/`ExamChoice` row parsers
  plus four pure helpers, each a direct port of specific
  `exam-attempt.tsx`/`exams/page.tsx` logic: `groupExamQuestionRows()`
  (flat rows -> questions, sorted by `order_index`), `toggleChoice()`
  (single-select always replaces the selection; multi-select toggles
  membership -- identical to `toggleSingle`/`toggleMulti`),
  `formatExamTime()` (identical `m:ss` formatting), and
  `attemptsRemaining()` (the `max_attempts - attemptsUsed`, floored at 0,
  logic used by both the list page's "x/y attempts used" display and the
  detail page's exhaustion guard).
- `lib/exams/exam_attempt.dart`: a `Timer.periodic` countdown (mirroring
  the web version's `setTimeout`-based effect), single_choice/true_false
  as a `RadioGroup<String>` (see ADR 0030 for why not the deprecated
  `RadioListTile` API directly) and multi_choice as `CheckboxListTile`s,
  `short_answer` shown as "not auto-gradable yet" exactly like the web
  version. Submits only through `submit_quiz_attempt()`.
- `lib/exams/exam_detail_screen.dart`: prior-attempts history, the
  already-passed guard, and the attempts-exhausted guard, mirroring
  `exams/[quizId]/page.tsx` exactly.
- `HomeShell` gained a sixth tab. Six destinations is the practical
  ceiling for a Material `NavigationBar` before it gets visually cramped
  on narrow phones -- a real, named UX concern (not silently ignored) to
  revisit with a `Drawer` or `NavigationRail` once more tabs are added in
  a future phase, not something to solve prematurely for a slice that
  still fits.

## Consequences

- 11 new unit tests (`exam_test.dart`): question grouping/sorting/a
  `short_answer` question with no choices, `toggleChoice()`'s single- and
  multi-select behavior, `formatExamTime()`'s three real cases, and
  `attemptsRemaining()`'s null/normal/floored-at-zero cases. 54
  `flutter test`s total (was 43).
- `flutter analyze` stayed clean; `flutter build web` still succeeds.
- The web app's own known limitation (client-side-only timer, no
  server-side exam session) applies identically here -- not a new gap
  introduced by the port, the same honest boundary carried over.
