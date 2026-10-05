# ADR 0063: CTF Events/leaderboard screen on mobile

## Status

Accepted.

## Context

Building dynamic CTF scoring (ADR 0062) required auditing mobile's CTF
screens for parity, which surfaced a real, previously undocumented gap:
mobile's `/ctf` equivalent (`ctf_list_screen.dart`) had only ever been
the flat `ctf_challenges_public` list. Web's whole Arena/mission UI
(event grouping with a live/upcoming/ended badge, a ticking countdown
banner, and `ctf_event_leaderboard()`'s cross-user aggregate -- ADR
0021) had no mobile counterpart at all; `ctf_events` was read nowhere
outside the admin screens (ADR 0053).

Reading `/ctf/page.tsx`, `/ctf/events/[eventId]/page.tsx`, `lib/ctf/
event-status.ts`, and `event-status-banner.tsx` confirmed this needs no
new Route Handler: `ctf_events`/`ctf_challenges_public` are plain
RLS-scoped reads, and `ctf_event_leaderboard()` is an existing
`SECURITY DEFINER` RPC the same as every other cross-user aggregate this
app calls directly from mobile today.

## Decision

- `lib/ctf/ctf_event.dart` (new): pure port of `lib/ctf/event-status.ts`'s
  `ctfEventStatus()` and `event-status-banner.tsx`'s `formatDuration()`
  -- including its one real quirk, preserved rather than "fixed": once a
  duration is a day or more, seconds never show again, and if the hour
  component is exactly zero the minutes don't show either (e.g. "1d 0h",
  not "1d 0h 45m"). Also `CtfEventSummary`, `CtfEventDetail`,
  `CtfLeaderboardEntry` (mirrors `types/database.ts`'s own
  `CtfLeaderboardEntry`).
- `lib/ctf/ctf_challenge.dart`: `CtfChallenge` gained `eventId` (null for
  an independent challenge), needed to replicate `/ctf/page.tsx`'s own
  `independentChallenges = challenges.filter((c) => !c.event_id)` split.
- `lib/ctf/ctf_list_screen.dart` (rewritten): now fetches `ctf_events`
  (published, ordered by `starts_at`) alongside the existing challenge
  fetch, rendering an "Events" section (title + live/upcoming/ended
  chip, tapping opens the new detail screen) above "Independent
  challenges" (the event-linked ones filtered out) -- the same two-group
  layout `/ctf/page.tsx` has.
- `lib/ctf/ctf_event_detail_screen.dart` (new): `CtfEventDetailScreen`
  loads the event row, its own challenges (via `ctf_challenges_public`
  filtered by `event_id`, same `current_points` display as the flat
  list), the signed-in user's solved-challenge-id set, and
  `ctf_event_leaderboard()`'s rows, then renders a ticking status banner
  (`_EventStatusBanner`, a private `StatefulWidget` with its own 1s
  `Timer.periodic`, same encapsulation as web's client component --
  renders nothing at all when the event has no time window, matching
  `event-status-banner.tsx` exactly) above a challenges list (tapping a
  challenge opens the existing `CtfDetailScreen`, then refreshes on
  return) and a leaderboard list (rank, display name, total points,
  the signed-in user's own row highlighted).

## Why

A private nested `_EventStatusBanner` widget, rather than inlining the
timer into `CtfEventDetailScreen`'s own state, mirrors web's own
component split (a server-rendered page wrapping a small ticking client
component) and keeps the 1s `setState` calls scoped to just the banner
instead of rebuilding the whole challenges/leaderboard list every
second.

## Consequences

- +11 `flutter test`s (`ctf_event_test.dart`: 6 `ctfEventStatus` cases
  mirroring `event-status.test.ts` exactly, 4 `formatCtfEventDuration`
  cases covering the day/hour-zero quirk) -- 213 `flutter test`s total
  (was 202).
- `flutter analyze` stays clean (the two pre-existing `RadioListTile`
  deprecation infos are the only issues, unrelated to this phase).
  `flutter build web` succeeds both with and without `API_BASE_URL` (no
  new Route Handler, so neither config changes this phase's behavior).
- Closes the CTF Events/leaderboard gap named in RELEASE_CHECKLIST.md
  while auditing ADR 0062's mobile parity. No named mobile-vs-web gap
  remains anywhere in this app's CTF coverage.
