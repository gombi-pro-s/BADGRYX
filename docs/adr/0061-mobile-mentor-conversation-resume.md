# ADR 0061: Mentor conversation resume on mobile

## Status

Accepted.

## Context

ADR 0059/0060 both named the same remaining Mentor limitation in
passing rather than fixing it: mobile's `MentorScreen` always starts an
empty conversation, even for a context where the web app would resume
the most recent one. Before treating this as another "mirror the web
limitation faithfully" case (like single-choice-only lesson quizzes or
no module reordering), it was worth actually checking whether resume is
real backend behavior or purely a client-side read.

Reading `apps/web/src/app/(app)/mentor/page.tsx` (lines 42-61) and
`apps/web/src/app/api/mentor/chat/route.ts` (lines 39-68) confirmed it's
the latter. The chat route never upserts a conversation by context: a
POST with no `conversationId` in its body always inserts a brand-new
`mentor_conversations` row, regardless of whether one already exists
for that `(user_id, context_type, context_id)` -- there's no unique
constraint on that tuple either. "Resume" is entirely page-load
behavior: `page.tsx` runs its own `mentor_conversations` select (most
recently updated row for this user+context, `context_id` matched
exactly or `.is(null)` for general/no-id contexts) and, if found, loads
that conversation's `mentor_messages` in creation order, then hands both
to `<MentorChat>` as props so the first POST from that page load already
carries the existing `conversationId` forward.

That means this is the same shape of gap every mobile deep-link phase
this session has closed: a client-side read mobile never performed,
against tables (`mentor_conversations`/`mentor_messages`) whose
`*_own` RLS already allows it directly, no Route Handler involved. Worth
fixing rather than naming as a permanent web/mobile divergence.

## Decision

- `lib/mentor/mentor_screen.dart`: `_MentorScreenState` gained
  `initState()` → `_loadExistingConversation()`, a direct port of
  `page.tsx`'s own lookup -- `mentor_conversations` filtered by
  `user_id`/`context_type`/`context_id` (`.isFilter('context_id', null)`
  for the general/no-id case, matching `.is("context_id", null)` on
  web), ordered by `updated_at` descending, `limit(1)`, `maybeSingle()`;
  on a hit, loads that conversation's `mentor_messages` ordered by
  `created_at` and populates `_conversationId` plus `_messages` before
  the first real paint. A `_loadingHistory` flag shows a spinner in the
  message area while this resolves, instead of flashing the empty-state
  copy first.
- A failure during this lookup (no session yet, a transient network
  error) is swallowed and the screen just starts fresh -- the same
  outcome as web's `.maybeSingle()` returning `null` when nothing
  matches, not a new failure mode.

## Why

No new Route Handler: `/api/mentor/chat` already only reuses a
conversation when the caller supplies its id back, which is exactly
what happens once this screen's own lookup has populated
`_conversationId` -- the same contract web's `MentorChat` component
relies on after its own initial load.

## Consequences

- No new `flutter test`s (no new pure-logic function -- this is a
  stateful-widget lifecycle method against live Postgrest, same
  untestable-without-mocking shape as `_send()` already had). 200
  `flutter test`s total, unchanged.
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL`.
- Closes the last named Mentor gap anywhere on mobile: every context now
  both deep-links into its right mode (ADR 0059) and resumes its last
  conversation (this ADR) exactly like web does.
