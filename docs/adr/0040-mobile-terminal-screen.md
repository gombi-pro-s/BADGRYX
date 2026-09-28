# ADR 0040: Interactive lab terminal in the Flutter mobile app

## Status

Accepted.

## Context

ADR 0039 wired `requireApiUser()` into `/api/labs/[labInstanceId]/terminal`.
This ADR is the mobile half -- and it closes the last "not on mobile yet"
gap the mobile README and `RELEASE_CHECKLIST.md` named explicitly since
ADR 0026: terminal-backed labs showed an honest banner instead of a real
terminal.

Reading `lib/terminal/execute.ts` and `apps/web`'s own `terminal.tsx`
client confirmed there is no interpreter to port: the entire tokenizer,
virtual filesystem, and multi-host ssh/exit pivoting engine (736 lines
across `lib/terminal/`) runs server-side behind the Route Handler.
`terminal.tsx` itself is a thin client -- POST a command string, render
`{ output, cwd, user, hostname }`, keep a transcript -- the same shape as
the Mentor and Scanner screens this session already built. Command-
history recall (up/down arrow) is the one piece of `terminal.tsx` that
doesn't translate: a touch keyboard has no arrow keys to bind it to, so
building it would mean inventing a different feature, not porting this
one.

## Decision

- `lib/labs/terminal.dart`: `TerminalEntry` (command/output pair) and the
  pure `formatTerminalPrompt(user, hostname, cwd)` helper, mirroring
  `terminal.tsx`'s `promptString()` exactly (a "connecting..." status
  until every field is known).
- `lib/labs/terminal_screen.dart`: the terminal UI -- a dark, monospace
  transcript, a bottom command-input row showing the live prompt, and a
  silent "connect" call (an empty command, exactly like `terminal.tsx`'s
  own connect effect) on open to learn the real user/hostname/cwd before
  anything is typed. Every command is a real `POST` to
  `<apiBaseUrl>/api/labs/{labInstanceId}/terminal` with `Authorization:
  Bearer <session.accessToken>` -- the same Bearer path the Mentor and
  Scanner screens use. Degrades to a plain "not configured on this
  build" message when `API_BASE_URL` is unset, same pattern as those
  two screens.
- `lib/labs/lab_workspace.dart` gained a `hasTerminal` field and an
  "Open terminal" button, shown once a lab instance exists (whether
  still in progress or already solved) for a terminal-backed lab --
  pushed as `TerminalScreen(labInstanceId: instance.id)`.
- `lab_detail_screen.dart`'s banner for terminal-backed labs was rewritten
  from "not available on mobile yet" to describe the real feature and
  name the one honest gap (history recall) instead.

## Why

- **Porting the client, not inventing an interpreter**, keeps this
  screen's behavior identical to the web app's -- the same rule ADR 0034
  applied to the Mentor's NDJSON parsing.
- **Naming history recall as a deliberate non-port** rather than a
  missing feature is the same honesty this session has applied
  throughout (general-only Mentor modes, pasted-snippet-only Scanner
  uploads, read-only Billing): a mobile terminal doesn't need feature
  parity with a desktop keyboard shortcut to be a real, complete
  terminal for its own platform.
- **The "Open terminal" button lives in `LabWorkspace`, not
  `LabDetailScreen`**, because only `LabWorkspace` tracks whether a lab
  instance has actually been started -- pushing the button up would have
  needed a callback just to duplicate state `LabWorkspace` already owns.

## Consequences

- +3 unit tests (`terminal_test.dart`: connecting/connected/partial-info
  cases for `formatTerminalPrompt()`) -- 89 `flutter test`s total (was
  86).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL`.
- Closes the mobile app's last named "not on mobile yet" gap for labs.
  Remaining, still-honest mobile gaps: the Cyber Range's own scoring/
  scenario UI beyond the terminal itself, every admin/instructor screen,
  multi-file scan upload, AI-enriched findings, manual finding-status
  transitions, and Billing checkout/upgrade/cancel.
