# ADR 0062: Dynamic CTF scoring

## Status

Accepted.

## Context

`ctf_events.scoring_type = 'dynamic'` has existed since the original
content model (20260921000008) and the admin UI has let staff pick it
since the Arena/mission UI phase (ADR 0021) -- but `submit_ctf_flag()`
always copied `ctf_challenges.points` flatly regardless of scoring type.
Both admin event forms (web and mobile) disclosed this honestly:
"picking it stores the intent but challenges still score at their fixed
points." `RELEASE_CHECKLIST.md` named it as a real, known gap rather
than silently ignoring the unused enum value.

Before building it, this phase checked what `ctf_event_leaderboard()`
(ADR 0021/20260922000026) actually sums: `points_awarded`, the value
frozen onto each `ctf_submissions` row at the moment that user solved --
never a live recomputation. That's the correct, standard CTFd-style
contract already: a dynamic challenge's value decays as more competitors
solve it, but each solver keeps whatever they earned at solve time. The
leaderboard function needed zero changes; only the one place that still
computed a flat value -- `submit_ctf_flag()` -- needed to change.

Solve-count tracking already existed too: `ctf_submissions`' own partial
unique index (`ctf_submissions_one_correct_per_user`) guarantees
`count(*) WHERE correct = true` for a challenge is an exact, cheap solve
count. No new table was needed.

## Decision

- New `ctf_challenges.min_points` column (nullable integer, `CHECK
  (min_points IS NULL OR (min_points >= 0 AND min_points <= points))`)
  -- the decay floor. `NULL` defaults to half of `points`, so every
  already-seeded challenge behaves sensibly the moment an event's
  `scoring_type` flips to `dynamic` without needing a backfill.
- New `ctf_challenge_current_points(p_challenge_id)` SQL function: the
  single source of truth for "what would solving this challenge award
  right now." Independent challenges (`event_id IS NULL`) and
  static-scoring events always return the flat `points` value --
  unchanged behavior. A dynamic-scoring event's challenge decays
  **linearly** from `points` to its floor over its first 10 solves (a
  fixed, documented constant, not a per-challenge decay-rate knob --
  deliberately the one extra piece of state this feature needs beyond a
  floor), then stays flat at the floor.
- `ctf_challenges_public` gained a `current_points` column (appended
  after the existing columns, since `CREATE OR REPLACE VIEW` can't
  reorder) calling the same function -- learner-facing pages now display
  this instead of the static `points`, so the display and the grading
  function can never disagree.
- `submit_ctf_flag()`'s one change: `v_points := v_challenge.points`
  became `v_points := public.ctf_challenge_current_points(p_challenge_id)`,
  called **before** this solve's own `INSERT`, so the Nth solver's score
  is always based on however many solves existed before theirs (the
  first solver sees a solve count of 0 and gets the full value).
  Everything else in the function -- auth check, idempotent
  already-solved return, flag hash comparison, skill evidence, audit log
  -- is byte-for-byte unchanged.
- Web: admin challenge form gained a "Min points" field (optional,
  validated `<= Points`); both admin event forms' disclaimers were
  rewritten from "not implemented yet" to explain the real decay/floor
  behavior; the challenge detail page and the event detail page now
  select and display `current_points`, with a "(decaying)" /
  "(started at N, decaying)" note when it differs from `points`.
- Mobile: `AdminCtfChallenge` gained `minPoints`; the admin challenge
  form gained the matching "Min points" field and validation;
  `CtfChallenge` gained `currentPoints`, and both the flat CTF list and
  the challenge detail screen display it (with the same "decaying" note
  on the detail screen) instead of the static `points`. The admin event
  form's disclaimer text was rewritten the same way as web's.

## Why

Computing the decayed value once, in one SQL function, and having both
the view and the grading function call it is what makes "the display
never disagrees with what you'd actually be awarded" a structural
guarantee rather than something that has to be kept in sync by hand
across web, mobile, and the grading path.

A fixed 10-solve linear decay window (rather than a per-challenge
decay-rate column) was chosen because it is the one piece of extra
state this feature genuinely needs -- a floor -- without opening a
second knob with no seeded data to justify a particular default.

## Consequences

- New migration `20260922000031_ctf_dynamic_scoring.sql` and SQL
  regression test `027_ctf_dynamic_scoring.sql` (6 assertions: first
  solver gets full value, second solver decays by one step,
  `ctf_challenges_public.current_points` matches what the next solve
  would award, the floor is reached and never breached after enough
  solves, a static-scoring event never decays). All pre-existing SQL
  regression tests still pass against the full migration chain.
- Web: `tsc --noEmit` clean, ESLint clean, `npx vitest run` unchanged at
  316 tests (the new logic lives in SQL, tested there -- no new JS pure
  logic), `npm run build` succeeds, and the 9 pure-HTTP "mobile API
  auth" e2e tests still pass (no Route Handler touched by this phase).
- Mobile: +2 `flutter test`s (202 total, was 200); `flutter analyze`
  clean; `flutter build web` succeeds both with and without
  `API_BASE_URL`.
- This phase did **not** build a learner-facing CTF Events screen on
  mobile (grouping, live/upcoming/ended badges, countdown, leaderboard --
  web's Arena/mission UI, ADR 0021). That turned out to be its own,
  separate, previously-undocumented mobile gap discovered while auditing
  this one: mobile's `/ctf` equivalent has only ever been the flat
  `ctf_challenges_public` list (`ctf_list_screen.dart`), with no
  `ctf_events` read anywhere outside the admin screens. Named here
  honestly rather than silently expanding this phase's scope to cover
  it.
