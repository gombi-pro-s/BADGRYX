# ADR 0021: CTF events, timers, and a leaderboard — the schema already planned for this

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had "Arena/mission UI (CTF timers/leaderboard)" as
not started. What was actually missing turned out to be narrower than it
sounded: `ctf_events` (`slug`, `title`, `scoring_type`, `starts_at`,
`ends_at`, `published`) and `ctf_challenges.event_id` have existed since
the original content model (`20260921000008_content_model.sql`), with real
RLS already in place — nothing had ever built the UI for them. `/ctf`
never grouped challenges by event, no page rendered an event's timing, and
nothing aggregated `ctf_submissions` across users into a ranking.

`ctf_submissions`' own RLS
(`ctf_submissions_select_own_or_staff`) is owner-only by design — a
learner's per-challenge submission history is theirs. A leaderboard is a
narrower, different thing: a cross-user *aggregate* (total score, solve
count, last-solve time), never which specific challenges a rival solved or
when. Exposing that aggregate needs a SECURITY DEFINER function that
deliberately, narrowly bypasses `ctf_submissions`' row ownership — the
same reasoning behind every other "one function is the only way to see/do
X across users" decision in this schema.

## Decision

- `ctf_event_leaderboard(p_event_id)` (`20260922000026_ctf_event_leaderboard.sql`):
  `STABLE SECURITY DEFINER`, returns `(user_id, display_name, total_points,
  solved_count, last_solve_at)` — never a challenge id, never a per-
  submission row. Ranked by total points desc, ties broken by earliest
  last-solve (standard CTF ranking: whoever reached that score first
  wins the tie). A draft (unpublished) event's leaderboard is staff-only,
  mirroring `ctf_events_select_published_or_staff` on the event row
  itself — an unpublished event shouldn't be readable through a side
  door.
- Admin: `/admin/ctf-events` (list/create/edit/publish-toggle, mirroring
  the announcements admin pattern). Challenge create/edit forms
  (`challenge-form-fields.tsx`) gained an optional event `<select>`.
- Learner: `/ctf` now groups published events (with a live status badge —
  upcoming/live/ended) above the existing "independent challenges" list
  (challenges with no `event_id`, unchanged behavior). `/ctf/events/[eventId]`
  is the event detail page: a ticking countdown/status banner, the
  event's own challenge list, and the leaderboard.
- `lib/ctf/event-status.ts`: pure `ctfEventStatus(startsAt, endsAt, now)`,
  shared by the server-rendered list badge (a static snapshot at render
  time) and the client-side ticking countdown — the same "pure logic
  usable both server- and client-side" split as `lib/mentor/modes.ts`.
  Direct unit tests (6 assertions), unlike most of this app's RLS-adjacent
  logic which can only be verified through SQL tests.

## Why

`ctf_scoring_type`'s `'dynamic'` value has existed in the schema the whole
time and is still completely inert: `submit_ctf_flag()` always awards a
challenge's fixed `points`, regardless of `scoring_type`. Implementing
decaying/dynamic scoring is a real, separate feature — it touches a
security-critical `SECURITY DEFINER` grading function and deserves its own
design pass (how decay works, what the floor is, whether it's
per-challenge or per-event config), not a rushed addition bolted onto a
UI-scoped phase. Building it here would have been scope creep beyond what
"Arena/mission UI" asked for. Instead: the admin UI for choosing "dynamic"
scoring says outright, next to the control, that picking it doesn't change
scoring yet — visible at the point of use, not just in a doc nobody
reads before clicking it.

## Consequences

- New SQL regression test (`supabase/tests/024_ctf_event_leaderboard.sql`,
  5 assertions): correct ranking with a real tie-break, an incorrect
  submission never contributing to the aggregate, a plain user unable to
  read another user's raw `ctf_submissions` row even though the
  leaderboard function still returns their aggregate, and the
  draft-event-is-staff-only guard in both directions.
- 6 new unit tests for the pure `ctfEventStatus()` classifier. 274 unit
  tests total (was 268).
- `ctf_scoring_type = 'dynamic'` remains inert, same as before this
  phase — not silently implemented, not silently ignored; tracked here
  and disclosed in the admin UI itself.
- 1 new e2e test (`/admin/ctf-events`' own auth wall). 24 e2e tests total.
- A real authenticated click-through (create an event, assign challenges,
  watch the countdown and leaderboard update as different users solve)
  needs a provisioned Supabase project, the same limitation as every
  other admin-CMS/learner flow in this sandbox.
