# ADR 0052: Reports screen on mobile

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md`'s mobile-gap bullet had listed "report moderation"
as an admin-shaped gap -- that was a mislabel, caught while scoping this
phase. Reading `reports/page.tsx` + `[reportId]/page.tsx` + `actions.ts`
showed Reports is not staff moderation at all: it's a plain, self-owned
learner pillar (write a pentest report or methodology write-up, ask the
AI Mentor to critique it), reviewed by the Mentor only -- "separate from
a capstone's reviewed submission, and never affects your Skill Graph."
There is no reviewer role anywhere in this feature. It had simply never
been ported to mobile at all, unlike the Scanner/Billing/Organizations
gaps this session had been closing, which were partial.

The feature itself is plain RLS-scoped Postgrest CRUD on the `reports`
table (`pentest_report`/`methodology` kinds) -- no Route Handler needed,
same shape as org/admin announcements. The one real complication is
`/reports/[reportId]`'s "Ask Mentor to review" link, which deep-links
into `/mentor?contextType=report&contextId=...&mode=review_report` (or
`review_methodology`). ADR 0034 already scoped mobile Mentor to general
modes only, with context-specific deep links (lab/lesson/finding/
investigation/report) named as a gap rather than built. Extending Mentor
itself to support a `report` context is real additional work (two new
modes, context-aware mode filtering, passing `contextType`/`contextId`
through the chat request) that belongs to Mentor's own scope, not
Reports' -- so this phase does not do it. "Ask Mentor to review" opens
the existing general-mode Mentor screen instead of a true deep link,
named here and in the mobile README as the gap it narrows ADR 0034's
"no deep links yet" down to, not a new one.

## Decision

- `lib/reports/report.dart` (new): `Report` row parser and the pure
  `reportKindLabel()`, mirroring `reports/page.tsx`'s `KIND_LABELS[r.kind]
  ?? r.kind` fallback exactly.
- `lib/reports/reports_screen.dart` (new): `ReportsListScreen` (list +
  FAB) and `ReportFormScreen` (combined create/edit, same reasoning as
  every other such screen in this app for why one screen replaces the
  web's two pages) with a kind dropdown, markdown content field, delete,
  and an "Ask Mentor to review" action in edit mode that pushes the
  existing `MentorScreen()`.
- `lib/home/more_screen.dart` gained a "Reports" entry.

## Why

Building Reports now rather than waiting for Mentor's context-deep-link
work to land first means the CRUD half of this pillar -- writing,
editing, and organizing reports -- is real and usable today; a user who
wants the Mentor's report-specific lens can already open AI Mentor
separately and paste/describe what they wrote, same as before this
phase, just without the one-tap deep link.

## Consequences

- +5 `flutter test`s (`Report.fromRow` parsing + null-content fallback,
  `reportKindLabel`'s two known kinds plus its raw-value fallback) -- 156
  `flutter test`s total (was 151).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this screen needs neither).
- Corrects `RELEASE_CHECKLIST.md`'s "report moderation" mislabel to
  describe what Reports actually is. Narrows ADR 0034's Mentor deep-link
  gap to specifically include `report`, rather than closing it.
