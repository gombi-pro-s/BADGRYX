# ADR 0027: Mobile CTF tab -- a second real vertical slice

## Status

Accepted.

## Context

ADR 0026 shipped the mobile app's foundation: real Supabase Auth and one
real data screen (Skills). `mobile/app/README.md` named everything else
-- labs, CTF, investigations, capstones, exams, Mentor, the scanner,
billing, every admin flow -- as honestly not yet built. CTF challenges are
the next self-contained, tractable slice: a published-challenge list and
a real flag submission, with no dependency on the terminal engine's
virtual filesystem/multi-host state (unlike labs) and no long-form content
rendering (unlike lessons/investigations).

## Decision

- `HomeShell` became a `StatefulWidget` with a `NavigationBar` (bottom
  tabs: Skills, CTF) instead of a single fixed screen -- the natural place
  to add a second tab now, and every tab hereafter.
- `lib/ctf/ctf_list_screen.dart`: reads `ctf_challenges_public` (the same
  view `apps/web`'s `/ctf` page reads -- published-only, flag hash never
  exposed by RLS), ordered by points.
- `lib/ctf/ctf_detail_screen.dart`: challenge detail + whether the current
  user has already solved it (`ctf_submissions` filtered to
  `user_id = auth.uid()`, owner-scoped by RLS exactly like the web app).
- `lib/ctf/flag_submit.dart`: mirrors `apps/web`'s `flag-submit.tsx`
  behavior and copy almost line for line -- calls the real
  `submit_ctf_flag()` RPC and renders whatever it returns. There is no
  code path in this widget that could decide "correct" on its own; the
  database is still the only grader, on mobile exactly as on web.
- `lib/ctf/ctf_challenge.dart`: plain data classes with `fromRow()`
  parsers, pure and unit-tested, mirroring the "parse the exact real row
  shape" discipline the web app's own TS types encode.

## Why

CTF was picked over labs specifically because it doesn't require porting
the terminal engine (a large, separate piece of logic) to be useful --
it's a complete, honest, self-contained slice on its own. Labs (especially
terminal-backed ones) are a real candidate for a future phase, but
porting `lib/terminal/*` faithfully deserves its own design pass, not a
rushed addition here.

## Consequences

- 4 new unit tests (`ctf_challenge_test.dart`): real row-shape parsing for
  both `CtfChallenge` and `CtfSubmissionResult`, including a null
  description staying null rather than being coerced to an empty string.
  22 `flutter test`s total (was 18).
- `flutter analyze` stayed clean; `flutter build web` still succeeds.
- A real authenticated click-through (browse challenges, submit a correct
  flag, see it recorded) still needs a provisioned Supabase project and a
  real device/emulator or browser session, the same limitation named in
  ADR 0026 and `mobile/app/README.md`.
