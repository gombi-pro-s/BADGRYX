# ADR 0004: Content model — structured tables, exams reuse the quiz schema

## Status

Accepted.

## Context

Section 29 of the spec requires structured content models administrable
through a CMS, not content hardcoded into frontend components. Section 22
requires an "exam" mode: limited/no hints, time limits, methodology
evaluation. On the surface this looks like a different feature from a
quiz, but structurally an exam is still "a set of graded questions with a
pass threshold."

## Decision

- `learning_paths → modules → lessons` model the taught curriculum.
- `quizzes` gained `is_exam`, `time_limit_minutes`, and `hint_policy`
  columns rather than a parallel `exams` table. A quiz with `is_exam = true`
  behaves as an exam (its `submit_quiz_attempt()` call records `assessment`
  skill evidence instead of `quiz` evidence — see ADR 0003).
- `quiz_questions`/`quiz_choices` are staff-only tables (never directly
  readable by a learner, since `is_correct` must stay hidden). Learners read
  `public.quiz_questions_for_attempt`, a view owned by the migration role
  that omits `is_correct` and only exposes published quizzes.
- `labs` model the lab engine's content: objectives, environment spec,
  hashed flags (`lab_flags`), leveled hints (`lab_hints`), and a
  `variant_count` for section 16's dynamic lab variants. `lab_instances`
  are the actual provisioned attempt per user.
- `ctf_challenges` reuses the same hashed-flag pattern; its `flag_hash`
  column means the base table can never be granted SELECT to
  `anon`/`authenticated` at all (RLS is row-level, not column-level, so it
  cannot hide one column from an otherwise-readable row). Learners read
  `public.ctf_challenges_public` instead.
- `capstones` are modeled separately from quizzes/exams because they
  combine multiple skills/labs and require a submitted report reviewed by
  staff, not an automatically graded pass/fail.

## Why

Reusing the quiz schema for exams avoids two near-identical grading code
paths (and two near-identical places to get evidence-recording wrong).
`is_exam` is the only differentiator needed; the differences the spec asks
for (time limits, hint policy, evidence type recorded) are all just column
values or evidence-type branches within `submit_quiz_attempt()`.

## Consequences

- A future "practice exam" or "certification exam" mode should still be a
  `quizzes` row with `is_exam = true`, not a new table, unless a genuinely
  new structural requirement (e.g. multi-day proctoring state) emerges.
- Anything with a secret answer key or flag must follow the
  staff-only-base-table + public-view pattern established here
  (`quiz_questions`/`quiz_choices` → `quiz_questions_for_attempt`;
  `ctf_challenges` → `ctf_challenges_public`), not a row-level `is_correct`
  RLS policy, which cannot hide a column.
