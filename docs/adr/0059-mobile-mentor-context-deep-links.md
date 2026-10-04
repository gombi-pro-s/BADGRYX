# ADR 0059: Mentor context-specific deep links on mobile

## Status

Accepted.

## Context

The one gap left anywhere on mobile after ADR 0058 closed every named
`/admin/*` item: mobile Mentor has been general-modes-only
(Explain/Hint/Teach/Analyze a failure) since ADR 0034, with every other
pillar's "Ask Mentor" entry point either missing or (Reports, ADR 0052)
opening the general-mode screen without its real context.

Reading `/api/mentor/chat/route.ts` showed this never needed a new Route
Handler or server-side work at all: it already accepts `contextType`/
`contextId` in its request body and `buildMentorContext()` already
resolves the grounding data for every context type server-side. The only
reason mobile couldn't reach `explain_finding`/`guide_investigation`/
`review_report`/`review_methodology` was that `MentorScreen` hard-coded
`contextType: 'general'` and its mode picker only ever rendered
`MentorMode.values` from a four-value enum -- a client-side gap, not a
missing capability.

Auditing every web page that deep-links into `/mentor` (`ctf`,
`investigation`, `lesson`, `finding`, `lab`, `report`) against what
mobile actually has today surfaced one pre-existing gap this ADR does
**not** close: mobile has no learner-facing lesson/path viewer at all
(only the admin authoring screens built in ADR 0055) -- so there is no
screen to hang a "lesson" Mentor entry point on in the first place. The
mobile README's "no lab/lesson/finding/investigation/report deep links"
line had been bundling that in as if it were the same kind of gap as the
other four; it isn't. This ADR closes lab, ctf, investigation, finding,
and report (all five already have a mobile detail screen); lesson stays
open, correctly named now as "no lesson viewer to attach it to" rather
than "no deep link."

A second, smaller inaccuracy fixed in passing: `lab_detail_screen.dart`'s
own in-app banner still said terminal command-history recall was
"web-only" -- a leftover from before ADR 0050 corrected that same framing
everywhere else. It's updated here since this phase was already touching
that file.

This phase deliberately does **not** add conversation-resume-on-reopen
(`/mentor/page.tsx`'s own lookup of the most recent `mentor_conversations`
row for a given user+context, so reopening a context's Mentor chat
continues where you left off). Mobile's general-mode Mentor screen never
had this either -- every open starts a fresh conversation -- so this
isn't a regression introduced by adding context support; it's named here
as its own, narrower, pre-existing gap rather than silently carried
forward.

## Decision

- `lib/mentor/modes.dart`: `MentorMode` extended from four values to all
  eight real modes; added `generalMentorModes`, `defaultModeForContext()`,
  `extraModesForContext()`, `modesForContext()` -- direct ports of
  `apps/web/src/lib/mentor/modes.ts`'s same-named functions, `contextType`
  passed as a plain string (same convention as this app's other
  database-enum fields) rather than a parallel context-type enum.
- `lib/mentor/mentor_screen.dart`: `MentorScreen` gained `contextType`
  (default `'general'`), `contextId`, `initialMode`, and `focusTitle`
  constructor parameters; the mode picker now renders
  `modesForContext(contextType)`; the POST body now sends the real
  `contextType`/`contextId`; a "Focused on: {title}" line renders when
  `focusTitle` is set, passed directly by the caller (it already loaded
  that record for its own screen) rather than this screen re-fetching it
  the way `/mentor/page.tsx`'s `resolveFocusTitle()` does.
- Real entry points added: `lab_detail_screen.dart` (hint),
  `ctf_detail_screen.dart` (hint), `investigation_detail_screen.dart`
  (guide_investigation), the Scanner finding card in
  `scan_detail_screen.dart` (explain_finding) -- each a small "Mentor"
  button next to the record's title. `reports_screen.dart`'s existing
  "Ask Mentor to review" button (ADR 0052) now passes `contextType:
  'report'`, the report's own id, and `review_report`/`review_methodology`
  based on `kind`, exactly mirroring `[reportId]/page.tsx`'s own
  `mentorMode` computation.

## Why

Passing `focusTitle` from the caller instead of adding a second fetch
inside `MentorScreen` keeps the screen itself free of a new round trip --
every caller already has the title in hand from loading its own detail
view.

## Consequences

- +6 `flutter test`s (`modes_test.dart`: `apiValue`/label mappings,
  `defaultModeForContext`, `extraModesForContext`, `modesForContext`) --
  194 `flutter test`s total (was 188).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (no new Route Handler, so neither config
  changes this phase's behavior).
- Narrows the mobile Mentor gap to exactly one named item: lesson context
  (blocked on there being no mobile lesson viewer at all, a separate and
  larger gap than a missing deep link) and conversation-resume-on-reopen
  (a pre-existing limitation, not new here).
