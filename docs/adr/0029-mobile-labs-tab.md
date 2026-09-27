# ADR 0029: Mobile Labs tab -- start/hints/flag, terminal explicitly deferred

## Status

Accepted.

## Context

After Home/Skills/CTF (ADRs 0026-0028), Labs was the next tractable
learner-facing pillar: unlike Investigations (mixed multiple-choice/
exact-text answer JSON) or a terminal-backed lab (the full virtual
filesystem/multi-host engine from ADR 0009/0023), a non-terminal lab's
core loop -- start guided/unguided, unlock hints, submit a flag -- is a
direct, self-contained port of `apps/web`'s `lab-workspace.tsx`.

## Decision

- `lib/labs/lab.dart`: `Lab`/`LabHint`/`LabInstance` row parsers and the
  pure `submissionCorrect()` helper, unit-tested against real row shapes
  including the `has_terminal` flag.
- `lib/labs/labs_list_screen.dart`: published labs + this user's own
  `lab_progress` for the "Completed" badge, mirroring `/labs` exactly.
- `lib/labs/lab_workspace.dart`: a direct port of `lab-workspace.tsx`'s
  state machine -- no instance yet -> start guided/unguided buttons (a
  plain `lab_instances` insert, RLS-scoped to the caller); an instance
  exists -> hints (guided only, `unlock_lab_hint()` RPC then a direct read
  of the now-unlocked `lab_hints.content`) and flag submission
  (`submit_lab_flag()` RPC). Identical wording to the web version's
  copy/labels where there's no reason to differ.
- `lib/labs/lab_detail_screen.dart`: renders the lab plus **an honest
  banner for every lab, not just terminal-backed ones** -- either "this
  lab has an interactive terminal on the web app, not available on mobile
  yet" or the pre-existing "this lab doesn't have a terminal environment
  yet" (mirroring the exact web-app copy for that second case). A learner
  should never wonder whether a missing terminal here means the lab is
  broken versus mobile genuinely not supporting it yet.
- `HomeShell` gained a fourth tab (Home/Labs/Skills/CTF).

## Why

Porting `lib/terminal/*` (the interpreter, the multi-host Cyber Range
extension, the server-side execution engine's RLS-narrow escalation
pattern) faithfully to a mobile client is real, separate design work --
doing it as a rushed addition here would risk exactly the kind of subtly
wrong reimplementation this session's rigor exists to avoid. Shipping the
flag-submission/hint loop now, with an honest "no terminal yet" banner
rather than silently hiding terminal-backed labs or pretending a terminal
exists, is the same "narrower but honest" choice this project has made
repeatedly (e.g. ADR 0019's manual-only load-test scripts, ADR 0009's own
"not a provisioned live host" scope statement).

## Consequences

- 7 new unit tests (`lab_test.dart`): real row parsing for `Lab` (including
  a `has_terminal: false` case and a null description), `LabHint`,
  `LabInstance` (guided and unguided), and `submissionCorrect()`'s both
  outcomes. 33 `flutter test`s total (was 26).
- `flutter analyze` stayed clean; `flutter build web` still succeeds.
- The terminal/Cyber Range simulator remains web-only, named as such in
  the UI itself (the banner) and in `mobile/app/README.md`, not silently
  omitted.
