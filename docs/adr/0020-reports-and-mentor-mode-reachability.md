# ADR 0020: Reports (Mentor-reviewed) — and a real bug found while building them

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md`'s AI Mentor section had flagged `REVIEW_REPORT`/
`REVIEW_METHODOLOGY` as not implemented: "this platform genuinely has no
written-report feature (a document a learner produces and the Mentor
reviews)." That was half right. `lib/mentor/prompt.ts` already had real
mode-instruction logic for both modes, and `api/mentor/chat/route.ts`
already accepted them — there was simply no `reports` table, so
`modeInstructions()` for both modes said "not implemented yet" rather than
reviewing anything, and `lib/mentor/__tests__/prompt.test.ts` asserted
exactly that disclaimer as correct behavior.

This is deliberately separate from `capstone_submissions.report_content`,
which already existed and is reviewed by a human staff member
(`review_capstone_submission()`, ADR 0008) as part of a graded capstone. A
`reports` row is personal practice: written freely, reviewed only by the
Mentor, never graded, and produces no `skill_evidence` — the Mentor cannot
write to that table at all (see `20260922000001_ai_mentor.sql`'s header).

While wiring this up, found a real, separate, and larger bug: **the
context-specific Mentor modes were unreachable from the UI even before
this change.** `explain_finding` and `guide_investigation` already had
real prompt logic and were already accepted by the API, and their deep
links already set the right `contextType`/`contextId` — but
`mentor-chat.tsx`'s mode picker only ever offered 4 generic modes
(explain/hint/teach/analyze_failure) and its `mode` state always
initialized to `"explain"`, with nothing anywhere deriving a
context-appropriate mode. A user who clicked "Ask Mentor" from a scan
finding got the finding's data injected into context, but every message
they sent still ran under the generic EXPLAIN instructions, never
EXPLAIN_FINDING — the exact mode that mattered was implemented end-to-end
and simply never reachable.

## Decision

**Reports:**
- `reports` (`20260922000025_reports.sql`): `user_id`, `kind`
  (`pentest_report` | `methodology`), `title`, `content_markdown`. RLS
  mirrors `mentor_conversations` exactly: owner read/write, staff
  read-only (moderation).
- `'report'` added to `mentor_context_type` (same shape as the earlier
  `'investigation'`/`'finding'` additions).
- `buildFocusDetail()` (`lib/mentor/context.ts`) gained a `report` branch,
  RLS-scoped like every other branch there.
- `modeInstructions()` for `review_report`/`review_methodology` now
  actually critiques the report/write-up in context (structure, whether
  each claim is backed by evidence, what's missing) instead of the
  disclaimer. The disclaimer tests in `prompt.test.ts` were rewritten to
  assert the new grounded behavior — the old tests were pinning the bug in
  place, the same shape of problem the `explain_finding` test already
  guarded against for that mode.
- `/reports`: list + create a report (title, kind, markdown body).
  `/reports/[reportId]`: edit, delete (nothing else references a report's
  id, so — like announcements, ADR 0017 — a real delete is offered, not
  just unpublish), and "Ask Mentor to review", deep-linking with
  `mode=review_report` or `mode=review_methodology` depending on the
  report's own `kind`.

**Mode reachability (the bug):**
- New pure module `lib/mentor/modes.ts` (no `"server-only"` — unlike
  `context.ts`, this must be importable from the client-side mode picker):
  `ALL_MENTOR_MODES` (single source of truth, replacing a hand-maintained
  copy in `route.ts` — the same drift risk AUDIT-009 found for context
  types), `defaultModeForContext()`, `extraModesForContext()`.
- `/mentor` now accepts `?mode=`, validated against `ALL_MENTOR_MODES`;
  when absent or invalid it falls back to `defaultModeForContext(contextType)`
  rather than always `"explain"`.
- `MentorChat`'s mode picker now renders `GENERAL_MODES` plus whatever
  `extraModesForContext()` returns for the current context, so the
  context-specific mode is always an explicit, visible, selectable pill —
  never only an invisible default a user can't get back to.
- Every existing "Ask Mentor" deep link (lesson, lab, ctf, investigation,
  finding) now passes an explicit `&mode=` matching what
  `defaultModeForContext()` would already compute, so each one is
  self-describing rather than relying on the fallback.

## Why

Two separate defects, two separate fixes, reported together because the
second was found only by trying to finish the first properly: building
Reports meant asking "does `review_report` actually get used anywhere?",
which meant tracing how a mode reaches the API — and that trace is what
surfaced that `explain_finding`/`guide_investigation` had the identical
problem already in production-shaped code, just never noticed because
nothing had exercised the actual client-to-API mode wiring end-to-end.
Fixing only the report side would have shipped a third mode with the same
latent unreachability the first two already had.

## Consequences

- New SQL regression test (`supabase/tests/023_reports.sql`, 8
  assertions): owner-only write, staff read-but-not-write, an unrelated
  user sees and can affect nothing (including the RLS-blocked-UPDATE
  0-rows-affected case from ADR 0017), and `'report'` composes correctly
  as a real `mentor_conversations.context_type` value.
- New unit tests: 11 for `lib/mentor/modes.ts` (pure, direct), plus
  `prompt.test.ts`'s two disclaimer tests replaced with three grounded
  ones (net +1). 268 unit tests total.
- While adding the e2e auth-wall test for `/reports`, caught a second real
  bug: `/reports` was missing from `middleware.ts`'s `PROTECTED_PREFIXES`.
  Not a security hole — `requireUser()` still blocked unauthenticated
  access — but it meant `/reports` was the one protected page that didn't
  preserve `?next=` through login, unlike every other one. Fixed by adding
  it to the list; audited the rest of `(app)`'s route folders against the
  list while there and confirmed every other one was already present.
- 23 e2e tests total (was 22).
- Reports are reviewed by the Mentor only — there is still no feature
  where a human staff member reviews a freeform report outside a
  capstone. That remains exactly the capstone review flow (ADR 0008),
  unchanged by this phase.
