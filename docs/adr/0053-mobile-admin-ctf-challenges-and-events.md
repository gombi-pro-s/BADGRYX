# ADR 0053: Admin CTF Challenges + CTF Events screens on mobile

## Status

Accepted.

## Context

Of the `/admin/*` pillars not yet on mobile (learning paths, labs, quizzes,
CTF challenges, CTF events, path import/export), CTF challenges and events
were the next smallest, bounded-CRUD pair -- the same shape as the Users
and Announcements screens already built (ADR 0049/0051), and tightly
coupled to each other (a challenge optionally belongs to an event; an
event's own page lists its challenges).

Reading `20260921000009_content_model_rls.sql` confirmed both
`ctf_challenges` and `ctf_events` carry a blanket
`FOR ALL ... USING (is_staff())` policy (the latter via
`20260922000028_blue_purple_scenario_linkage.sql`), same as every other
admin table this app already writes to directly over Postgrest -- no Route
Handler needed. Neither table's admin UI on web has a delete action
(a challenge/event may already have submissions or a leaderboard tied to
it), so mobile doesn't add one either.

The one real wrinkle is flag hashing. `apps/web/src/lib/security/flag-hash.ts`
is marked `server-only` and its own comment says hashing must happen "before
the plaintext ever leaves the server." Taken literally that would mean
mobile needs a Route Handler just to hash a flag -- but the actual plaintext
already originates wherever the staff admin types it, browser or phone
alike; hashing it on-device doesn't create a new place that plaintext is
exposed. What that comment is actually guarding against is a web browser
hashing it (or round-tripping it) via some separate client-side path instead
of the Server Action that already has it in the POST body -- not "hashing
outside of Next.js's own server is unsafe, full stop." Dart's `crypto`
package computes the exact same thing: lowercase hex SHA-256, byte-identical
to `encode(digest(flag, 'sha256'), 'hex')` (verified against two known
digests in `admin_ctf_test.dart`). `crypto` was already a transitive
dependency (pulled in by `supabase_flutter`), so this needed no new network
dependency, unlike `file_picker`/`http` before it.

## Decision

- `lib/admin/admin_ctf.dart` (new): `ctfCategories`/`ctfDifficulties`/
  `ctfScoringTypes` constant lists mirroring `LabCategory`/
  `DifficultyLevel`/`CtfScoringType`; `isValidCtfSlug()`; `hashCtfFlag()`
  (SHA-256 hex via `package:crypto`); `ctfEventTimeRangeError()` mirroring
  the `endsAt <= startsAt` rejection both event actions share;
  `AdminCtfChallenge`/`AdminCtfEvent` row parsers.
- `lib/admin/admin_ctf_challenges_screen.dart` (new): list + FAB, and a
  combined create/edit form (category/difficulty/event dropdowns, points,
  description, flag field hashed on submit, publish toggle with the same
  `log_audit_event` call `toggleChallengePublishedAction` makes) plus an
  inline skill tagger (`ctf_challenge_skills`: delete-then-insert, its own
  "Save skills" button, mirroring `skill-tagger.tsx`'s own separation from
  the main form) once a challenge has an id.
- `lib/admin/admin_ctf_events_screen.dart` (new): list + FAB, a combined
  create/edit form (scoring-type dropdown with the same "not implemented
  yet" dynamic-scoring note as the web form, optional start/end date-time
  pickers, publish toggle), and a read-only list of the event's own
  challenges in edit mode.
- `lib/admin/admin_screen.dart`: two new entries, and its stale comment
  (still calling Reports an admin gap as "report moderation" after ADR
  0052 corrected that) rewritten to list only what's actually still
  missing.
- `pubspec.yaml`: `crypto` promoted from transitive to a direct dependency.

## Why

Keeping flag hashing on-device rather than inventing a new Route Handler
(or a new SECURITY DEFINER RPC) for it stays consistent with this session's
established rule: a Route Handler exists only when the web app's own
feature already needed one. It also means this phase, like Users/
Announcements/Reports before it, adds no new backend surface at all --
every write here already has an authorization boundary that doesn't care
which client made the Postgrest call.

## Consequences

- +10 `flutter test`s (`isValidCtfSlug`, `hashCtfFlag` against two known
  digests plus a determinism check, `ctfEventTimeRangeError`'s four cases,
  both row parsers) -- 166 `flutter test`s total (was 156).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (neither new screen calls a Route Handler).
- `crypto` is now a direct dependency (previously transitive only).
- Narrows the remaining `/admin/*` mobile gap to learning paths, labs,
  quizzes, and path import/export.
