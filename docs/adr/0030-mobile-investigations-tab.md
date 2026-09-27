# ADR 0030: Mobile Investigations tab

## Status

Accepted.

## Context

After Home/Labs/Skills/CTF (ADRs 0026-0029), Investigations was the next
tractable pillar: real evidence artifacts, a mixed multiple-choice/exact-
text answer form graded server-side, and a private autosaved notes
scratchpad -- all a direct, faithful port of `apps/web`'s `/investigate`
pages rather than requiring new backend design.

## Decision

- `lib/investigations/investigation.dart`: row parsers plus three pure,
  directly-ported helpers, each mirroring specific web-app logic exactly:
  `groupQuestionRows()` (the flat-rows-to-questions grouping
  `investigate/[id]/page.tsx` does inline), `buildAnswersPayload()` (the
  exact payload shape `investigation-answers.tsx` sends to
  `submit_investigation_answers()` -- a multiple-choice answer wrapped in
  a one-element list, exact-text as a raw string, both defaulting
  emptily when unanswered), and `bestSubmissionByInvestigation()` (the
  list page's "highest score wins, not most recent" badge logic).
- `lib/investigations/notes_pad.dart`: a direct port of `notes-pad.tsx`'s
  debounced-autosave pattern (1-second `Timer`, upsert to
  `investigation_instances` on `(investigation_id, user_id)`) -- the same
  private, not-even-staff-readable scratchpad, same idle/saving/saved/
  error status line.
- `lib/investigations/investigation_answers.dart`: a direct port of
  `investigation-answers.tsx` -- single-select radio per multiple_choice
  question (via a `RadioGroup<String>` per question, Flutter's post-3.32
  replacement for `RadioListTile`'s now-deprecated `groupValue`/
  `onChanged`), a text field per exact_text question, and a submit that
  only ever renders whatever `submit_investigation_answers()` returns.
- `HomeShell` gained a fifth tab (Home/Labs/Investigate/Skills/CTF).

## Consequences

- 10 new unit tests (`investigation_test.dart`): `groupQuestionRows()`'s
  grouping/ordering/empty-choices behavior, `buildAnswersPayload()`'s four
  answered/unanswered × multiple-choice/exact-text combinations, and
  `bestSubmissionByInvestigation()`'s highest-score-wins logic across one
  and multiple investigations, including the case with zero submissions.
  43 `flutter test`s total (was 33).
- `flutter analyze` stayed clean after fixing one real, version-specific
  issue caught by the analyzer: `RadioListTile`'s `groupValue`/
  `onChanged` were deprecated in the installed Flutter version in favor
  of an ancestor `RadioGroup<T>` -- fixed by wrapping each question's
  choices in their own `RadioGroup<String>` rather than suppressing the
  warning.
- `flutter build web` still succeeds.
