# ADR 0050: Command-history recall on the mobile terminal

## Status

Accepted.

## Context

Every prior mobile phase (ADR 0040's own doc comment, the mobile README,
`RELEASE_CHECKLIST.md`) named command-history recall (up/down arrow) as
not built, reasoning that "a touch keyboard has no arrow keys to bind it
to." That reasoning conflated the on-screen software keyboard with
keyboard *input* in general: a Bluetooth or USB keyboard, or a software
keyboard app that draws its own arrow keys (e.g. Hacker's Keyboard,
widely used by exactly the kind of user this app is for), sends real
hardware `KeyDownEvent`s for ArrowUp/ArrowDown either way -- Flutter
receives these identically regardless of what drew them. The earlier
framing was wrong to call this impossible; it is a real, buildable
feature for the subset of users with such an input method, same as a
desktop browser user of the Flutter Web build (this repo's own CI/
sandbox verification target) typing on a real keyboard.

The remaining question was mechanical: does a `Focus` widget wrapping
the terminal's input `TextField` actually see an ArrowUp/ArrowDown event
*before* `TextField`'s own default text-editing shortcuts consume it?
Reading Flutter's `focus_manager.dart` confirmed key events are
dispatched by walking from the currently-focused leaf node up through
its `ancestors`, stopping at the first node whose `onKeyEvent` returns
`handled`; `editable_text.dart`'s own comments say its default shortcuts
are declared "near the top of the widget tree" (by `WidgetsApp`), which
is far above a `Focus` wrapped immediately around the `TextField` --
so the wrapping `Focus` sees the event first. This was then verified for
real with `tester.sendKeyEvent()` (see Decision below), not left as
inference from reading the framework source.

## Decision

- `lib/labs/terminal.dart` gained `TerminalHistoryStep` and the pure
  `recallTerminalHistory()`, a direct port of `terminal.tsx`'s
  `recallHistory()` -- including its one real quirk (ArrowDown while not
  currently browsing history clears the input, rather than being a
  no-op) -- faithfully ported, not redesigned.
- `lib/labs/terminal_screen.dart`: `_historyIndex` state (reset at the
  same two points `terminal.tsx` resets it: the `clear` command, and
  right before sending any other command), a `_commandHistory` getter
  over the transcript, and `_handleInputKey()` wired into a `Focus`
  wrapping the input `TextField`, returning `KeyEventResult.handled` for
  ArrowUp/ArrowDown so the event never reaches `TextField`'s own default
  vertical-navigation shortcuts.
- `test/labs/terminal_history_keys_test.dart` (new): a minimal
  `Focus`-wrapping-`TextField` harness, proving with
  `tester.sendKeyEvent(LogicalKeyboardKey.arrowUp)` (a real simulated
  hardware key event, not a call to the pure function directly) that the
  mechanism itself works -- recall across repeated presses, walking back
  down again, and that normal typing is unaffected by the wrapper.

## Why

A widget test that only called `recallTerminalHistory()` directly would
prove the *decision* logic but not the actual risk this ADR exists to
resolve -- whether Flutter's focus-dispatch order lets an ancestor
`Focus` intercept a key event before `TextField`'s own shortcuts do.
Simulating the real key event through the real widget composition is
what actually retires that risk.

## Consequences

- +11 `flutter test`s (7 `recallTerminalHistory` cases covering empty
  history, first/repeated ArrowUp, clamping at both ends, ArrowDown
  walking forward, and the clear-on-ArrowDown-while-idle quirk; 4
  widget-level key-event simulations) -- 141 `flutter test`s total (was
  130).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (unaffected either way).
- Retracts the "impossible on a touch keyboard" framing used in ADR
  0040, the mobile README, and `RELEASE_CHECKLIST.md` -- corrected in
  each to describe what is actually true: real on a hardware or
  arrow-key-capable software keyboard, simply absent from the stock
  on-screen keyboard itself.
