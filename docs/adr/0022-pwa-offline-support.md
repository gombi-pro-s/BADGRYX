# ADR 0022: PWA installability and a narrowly-scoped offline fallback

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had "PWA / offline support" listed as not started.
The app had no `public/` directory, no icons beyond a bare `favicon.ico`,
no web app manifest, and no service worker — a user could not install it
to a home screen/app list, and a lost connection produced whatever the
browser's own offline error page shows rather than anything this app
controls.

Almost every page in this app needs a live Supabase round trip: auth,
lessons, labs, CTF, Mentor, the scanner, reports. That's a real constraint
on what "offline support" can honestly mean here — this is not a
content-heavy app that can ship a meaningfully useful offline reading mode.

## Decision

- **Icons, zero new dependencies.** `app/apple-icon.tsx` (180×180) and two
  plain Route Handlers, `app/icons/192/route.tsx` and
  `app/icons/512/route.tsx`, each returning a `next/og` `ImageResponse` —
  Next's built-in Satori-based PNG renderer, already a transitive
  dependency of the framework itself, needing no new package. Real brand
  colors lifted from `globals.css` (`#0a0d12` background, `#2dd4bf`
  accent), not arbitrary placeholder colors. Deliberately plain Route
  Handlers rather than the `icon.tsx` file convention: that convention
  resolves to an internally-generated `/icon?<hash>` URL that isn't safely
  hand-referenceable from `manifest.ts`, whereas a Route Handler's URL is
  exactly the path you write.
- **`app/manifest.ts`** — the `MetadataRoute.Manifest` file convention,
  auto-linked into every page's `<head>` by Next itself (no manual
  `<link rel="manifest">` needed). References the two icon routes above,
  `start_url: "/dashboard"`, `display: "standalone"`.
- **`app/layout.tsx`** gained a separate `viewport` export (`themeColor`
  on `metadata` itself is deprecated in this Next.js version — confirmed
  via `next/dist/lib/metadata/types/metadata-interface.d.ts` and
  `generate-viewport.md`), with light/dark `prefers-color-scheme` variants
  matching the real design tokens.
- **`public/sw.js`** — hand-written, no Workbox/next-pwa/serwist (same
  zero-new-dependency discipline as the HTTP load test script in ADR
  0019). Exactly three responsibilities: precache `/offline` on install;
  on a failed navigation, fall back to the cached `/offline` page;
  cache-first-with-network-fallback for `_next/static/` build assets only
  (immutable, hash-versioned — safe to cache indefinitely). It never
  intercepts an API route, a Supabase call, or any other dynamic page —
  the one thing that would actually be dishonest here is silently serving
  stale authenticated content from a cache. `app/register-service-worker.tsx`
  is a one-effect client component, mounted once in the root layout, that
  registers it; a registration failure (unsupported browser, blocked
  storage) is swallowed since offline support is a progressive
  enhancement, not a requirement for the app to function.
- **`app/offline/page.tsx`** — a plain, unauthenticated static page
  outside the `(app)` route group, saying plainly that this app needs a
  live connection for almost everything rather than implying a broader
  offline mode than actually exists.

## Why

The alternative (a caching library, a fuller offline data layer) would
either add a dependency for what three lines of `fetch`/`caches` logic
already cover, or imply an offline capability this app doesn't have and
can't honestly claim given how much of it is live, per-user, RLS-scoped
data. Scoping the service worker to "static assets + one fallback page"
is the boundary that's both true and useful: real installability, a real
graceful offline navigation experience, faster repeat loads of unchanging
build assets — and no risk of ever serving a second user's cached
dashboard.

## Consequences

- 2 new e2e assertions (`e2e/smoke.spec.ts`): the landing page links a
  manifest whose two icon URLs both resolve to a real `200 image/png`
  response (not just "the file exists" — an actual fetch through the
  built production server), and `/offline` renders its real heading
  without hitting the auth wall. 26 e2e tests total (was 24).
  No new unit tests: icon generation and the service worker are both
  I/O/browser-runtime code, not pure logic, so there's nothing here that
  fits this app's existing "pure logic gets unit tests, I/O gets e2e/
  manual verification" split — see `lib/ctf/event-status.ts` vs.
  `event-status-banner.tsx` for the shape this follows.
- No SQL migration — this phase touches no schema.
- Nothing about the service worker can be verified through a real
  install/offline-toggle browser session in this sandbox (no way to open
  a real browser UI here); verified instead by `tsc --noEmit`, ESLint, a
  clean production build emitting all five new static routes
  (`/apple-icon`, `/icons/192`, `/icons/512`, `/manifest.webmanifest`,
  `/offline`), and the two e2e assertions above actually fetching the
  manifest and its icons through a running `next start` server.
