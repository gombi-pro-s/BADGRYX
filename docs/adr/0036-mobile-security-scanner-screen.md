# ADR 0036: Security Scanner screen in the Flutter mobile app

## Status

Accepted.

## Context

ADR 0035 wired `requireApiUser()` into `/api/scanner/scan`. This ADR is
the mobile half: a real Scanner screen. Like the AI Mentor, scan
submission runs server-side (the deterministic rule engine in
`lib/scanner/orchestrate.ts`) via a Route Handler, not a plain
Postgrest/RPC call -- but unlike the Mentor, reading a scan's own results
back (the scan row, its findings, its files) is plain Postgrest against
`scans`/`scan_findings`/`scan_files`, already RLS-scoped exactly like
every other mobile screen.

The web app's finding cards also support two write actions -- manual
status transitions (`transition_scan_finding_status()` RPC) and
"Enrich with AI" (`POST /api/scanner/findings/[findingId]/enrich`). Both
are deferred here, same honest-scope-boundary pattern as every prior
mobile phase (terminal-backed labs' "not on mobile yet" banner, the
Mentor's general-modes-only scope): findings are shown read-only, letting
this slice ship without needing the enrich route wired for bearer auth or
a mobile status-transition UI designed from scratch.

`uploaded_files` (multi-file upload) is also deferred -- it needs a file
picker, a new dependency this phase doesn't need. Only `pasted_snippet`
(paste code into a text field, same as typing into the web app's paste
tab) is built.

## Decision

- `lib/scanner/scan.dart`: `Scan`/`ScanFinding` row parsers, the
  `severityLabel`/`severityOrder` constants (mirroring
  `components/severity-badge.tsx`'s `SEVERITY_META` labels and Postgres's
  declared enum order), the pure `aggregatePosture()` helper (ports
  `scanner/page.tsx`'s inline posture-summing loop), and
  `formatScanTimestamp()`.
- `lib/scanner/scanner_list_screen.dart`: past scans (from `scans`,
  RLS-scoped) plus a combined posture summary across them, and a "New
  scan" FAB.
- `lib/scanner/new_scan_screen.dart`: title (optional) + filename + a
  paste-code text field, submitted via the same `requireApiUser()`
  Bearer-token path as the Mentor (`Authorization: Bearer
  <session.accessToken>` to `POST /api/scanner/scan`), navigating to the
  new scan's detail screen on success.
- `lib/scanner/scan_detail_screen.dart`: the scan's meta plus its
  findings (severity-coded, most-severe-first, matching the web app's
  ordering), each expandable to show evidence/explanation/impact/
  remediation/secure example -- read-only, no enrich or status-transition
  actions.
- `config/env.dart`'s `AppEnv.isMentorConfigured` renamed to
  `isApiConfigured`: `apiBaseUrl` is no longer Mentor-specific now that
  the Scanner's scan-submission screen shares it, so the "not configured
  on this build" gate needed a feature-neutral name. Both screens check
  the same flag.
- Wired into `MoreScreen`'s menu, alongside AI Mentor.

## Why

- **Read-only findings first, write actions later** keeps this phase
  scoped to what a fresh Bearer-auth-authenticated screen actually needs
  (submit + view), the same incremental-vertical-slice discipline as
  every prior mobile phase, rather than also designing a mobile status-
  transition UI or wiring the enrich route's auth in the same commit.
- **Pasted-snippet only** avoids adding a file-picker dependency for a
  first slice; `uploaded_files` support is a clearly named gap, not a
  silently missing feature.
- **Renaming `isMentorConfigured`** rather than adding a second,
  identically-behaved flag keeps `AppEnv` honest about what `apiBaseUrl`
  actually gates now (two Route-Handler-calling screens, not one).

## Consequences

- +8 unit tests (`scan_test.dart`: row parsing for both types including a
  failed scan's `error_message`, every `severityLabel` being real text
  not the raw enum value, `aggregatePosture()`'s single/multi-scan/empty
  cases, and `formatScanTimestamp()`) -- 77 `flutter test`s total (was
  69).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `API_BASE_URL`.
- Deferred and named, not silently missing: multi-file upload, AI
  enrichment, and manual finding-status transitions on mobile.
