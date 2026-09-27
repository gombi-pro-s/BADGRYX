# ADR 0032: Mobile Capstones tab, and restructuring the bottom nav behind "More"

## Status

Accepted.

## Context

Capstones was the next tractable pillar -- a plain report submission
(`capstone_submissions` insert, no RPC) plus skill/lab tags and
submission history, a direct port of `apps/web`'s `/capstones` pages.
But adding it as a seventh flat bottom-nav tab would have made the
scaling concern ADR 0031 explicitly flagged ("six is the practical
ceiling... revisit once more tabs are added") something to actually
revisit now, not defer again.

## Decision

- `lib/capstones/capstone.dart`: `Capstone`/`CapstoneSubmission` row
  parsers, the pure `latestStatusByCapstone()` helper (the list page's
  "submissions arrive newest-first, so the first one seen per capstone is
  the latest" logic), and a shared `capstoneStatusLabel` map.
- `lib/capstones/capstones_list_screen.dart` /
  `capstone_detail_screen.dart`: published capstones + latest-status
  badge; detail view with skill/lab tag chips, submission history with
  reviewer notes, and a plain report-submission form (a direct
  `capstone_submissions` insert -- no RPC exists for this, matching
  `apps/web`'s own `submitCapstoneReportAction`).
- **Navigation restructuring**: `HomeShell`'s bottom `NavigationBar` drops
  to five destinations (Home/Labs/Skills/CTF/More); Investigate, Exams,
  and the new Capstones all move to a plain `MoreScreen` list menu that
  pushes to each one. This is a real fix, not a workaround -- five is
  solidly within Material's comfortable range for a phone-width
  `NavigationBar`, and `MoreScreen` is exactly where Capstones' eventual
  siblings (Mentor, Scanner, Billing, any admin/instructor screen) belong
  too, so this restructuring only has to happen once. Investigate's and
  Exams' list screens gained their own `Scaffold`/`AppBar` (they
  previously relied on `HomeShell`'s shared one as `IndexedStack` tabs)
  since they're now pushed routes reached from `MoreScreen`.

## Why

Continuing to add flat tabs would have made the UI worse with every
future pillar (Mentor, Scanner, Billing, admin) while ADR 0031's own
"revisit" note sat unaddressed. Doing the restructuring now, while only
three screens need to move, is far cheaper than doing it later once
there are six or seven pushed screens to migrate at once.

## Consequences

- 7 new unit tests (`capstone_test.dart`): row parsing for both types
  (including a null `reviewer_notes`), `latestStatusByCapstone()`'s
  newest-first-wins logic across one and multiple capstones plus the
  zero-submissions case, and a check that every status label is real
  text rather than the raw enum value. 61 `flutter test`s total (was 54).
- `flutter analyze` stayed clean; `flutter build web` still succeeds.
- No behavior changed for Home/Labs/Skills/CTF; Investigate and Exams are
  reached one tap further in (Home tab bar -> More -> the screen) instead
  of directly -- a real, deliberate UX trade-off in exchange for a bottom
  nav bar that stays usable as more pillars are added.
