# ADR 0028: Mobile Dashboard tab

## Status

Accepted.

## Context

After ADR 0026 (auth + Skills) and ADR 0027 (CTF), the mobile app had no
"home" screen -- it opened straight into whichever tab was first. The web
app's actual landing page after login, `/dashboard`, is a short, simple
read (profile display name, active plan name, up to 5 announcements) with
no complex grading/RPC logic -- a natural, low-effort next real slice.

## Decision

- `lib/dashboard/dashboard_screen.dart`: `fetchDashboard()` runs the exact
  same three queries as `apps/web`'s `dashboard/page.tsx` -- `profiles`
  (own display name), `subscriptions` joined to `plans` filtered to
  `trialing`/`active`/`past_due` (or "Free" if none), and `announcements`
  filtered to `published = true` and not-yet-expired, ordered by
  `published_at` descending, limited to 5. RLS already scopes org
  announcements to orgs the user belongs to, same as web.
- `lib/dashboard/announcement.dart`: `Announcement.fromRow()` and the pure
  `planNameFromSubscriptionRow()` helper (the "Free" fallback logic),
  unit-tested directly rather than only through the widget.
- `HomeShell` gained a third tab, placed first (Home/Skills/CTF), matching
  the web app's own navigation priority (dashboard is where a session
  lands).

## Consequences

- 4 new unit tests (`announcement_test.dart`): real row parsing, the
  "Free" fallback with no subscription row, the real joined plan name,
  and the fallback again when a subscription row exists but its `plans`
  join is null. 26 `flutter test`s total (was 22).
- `flutter analyze` stayed clean; `flutter build web` still succeeds.
- Markdown announcement bodies are rendered as plain text on mobile (no
  markdown-rendering package added) -- `apps/web` uses `react-markdown`
  for lesson content but its own dashboard banner also renders
  `body_markdown` as plain text, so this matches the web app's actual
  behavior on this specific screen, not a reduced-effort shortcut.
