# ADR 0044: Manual finding-status transitions in the Flutter mobile Scanner

## Status

Accepted.

## Context

ADR 0036 named manual finding-status transitions and "Enrich with AI" as
gaps on the mobile Scanner's read-only detail screen. Reading
`finding-card.tsx` showed the two are independent: status transitions call
`transition_scan_finding_status()` directly as an RPC -- plain RLS-scoped,
no Route Handler -- while "Enrich with AI" calls
`/api/scanner/findings/{id}/enrich`, a Route Handler that would need the
same Bearer-auth wiring as Mentor/scan-submission/the lab terminal. That
makes status transitions the smaller, self-contained half of the gap, worth
closing on its own rather than waiting on the other.

`status-transitions.ts`'s `LEGAL_TRANSITIONS` is UI-only, by its own
comment: `transition_scan_finding_status()` re-validates every transition
server-side regardless, so this is only about which buttons to show, not an
authorization boundary to get exactly right client-side.

## Decision

- `lib/scanner/scan.dart` gained three ported const maps:
  `legalStatusTransitions` (mirrors `LEGAL_TRANSITIONS`),
  `statusActionLabel` (mirrors `STATUS_ACTION_LABELS`), and
  `findingStatusLabel` (mirrors `finding-status-badge.tsx`'s `STATUS_META`
  labels, colors dropped since severity already carries the mobile card's
  color).
- `scan_detail_screen.dart`'s `_FindingCard` became stateful over its own
  `status` (previously just the initial row value): a status `Chip` next
  to the severity badge, and, once expanded, one button per legal next
  status that calls the RPC and updates local state from the row the RPC
  returns -- the same "trust the RPC's returned row over an optimistic
  guess" pattern `finding-card.tsx`'s own `transition()` uses.

## Why

Reusing the web's exact transition graph and labels as plain Dart consts
avoids re-deriving lifecycle rules mobile has no way to get right
independently -- the source of truth stays the migration's
`transition_scan_finding_status()` function either way.

## Consequences

- +3 `flutter test`s (`legalStatusTransitions`: every status has an entry
  and only points at real statuses; every reachable status has both an
  action label and a status label; the three "terminal-sounding" statuses
  can still be walked back to `remediation_required`) -- 116
  `flutter test`s total (was 113).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (this feature needs neither).
- Narrows ADR 0036's Scanner gap to just "Enrich with AI" and multi-file
  upload, both still named rather than silently missing.
