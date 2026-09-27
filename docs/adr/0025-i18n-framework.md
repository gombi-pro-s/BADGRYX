# ADR 0025: An i18n framework -- cookie-based, no new dependency, honestly scoped

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had "i18n framework in place" as not started,
explicitly blocking content translations (ADR 0017 deferred an
`announcement_translations` table specifically because "there is no i18n
framework yet to ever render a translated string"). Nothing in this app
could render UI text in more than one language.

A full solution (`next-intl`, `[locale]`-segment routing restructuring the
entire `(app)` route tree, ICU MessageFormat pluralization) is real
infrastructure this app doesn't need yet to stop being blocked -- and
restructuring every route behind a locale segment is a large, risky
change to make in one phase. The honest, scoped question is narrower: can
this app render some real UI text in more than one language, in a way
that's actually correct (no half-translated pages, no silently blank
strings), without pretending to be more complete than it is?

## Decision

- `lib/i18n/locales.ts`: `SUPPORTED_LOCALES = ["en", "es"]`, `Locale` type,
  `isSupportedLocale()`. Adding a locale later means adding one dictionary
  file and one array entry.
- `lib/i18n/messages/{en,es}.ts`: flat key -> string dictionaries. `en.ts`
  is canonical (every key that exists anywhere must exist there); `es.ts`
  is typed `Partial<Record<keyof typeof en, string>>` -- a real dictionary
  is allowed to lag while a key is being translated.
- `lib/i18n/translate.ts` (pure, unit-tested): `translate(locale, key,
  params?)` looks up the target locale's dictionary, falls back to English
  for a missing key, and does `{param}` interpolation. No pluralization,
  no ICU MessageFormat -- neither is needed by anything this app currently
  renders, and adding either speculatively would be exactly the kind of
  unused abstraction this codebase avoids elsewhere.
- `lib/i18n/cookie.ts` (`getLocale()`, server-only) / `lib/i18n/actions.ts`
  (`setLocaleAction`, `"use server"`): a plain cookie
  (`icorepen_locale`), not URL-prefixed routing. Every route keeps its
  exact path (`/dashboard`, not `/es/dashboard`); only the strings a
  locale-aware page chooses to render change. This is the deliberate,
  smaller-scope choice: real URL-based i18n (SEO-indexable per-locale
  pages, locale in the path) would mean restructuring the entire `(app)`
  route group behind a `[locale]` segment -- a much bigger, riskier change
  than a phase like this should make in one pass.
- `components/locale-switcher.tsx`: a small client component rendering one
  toggle-chip button per supported locale, calling `setLocaleAction`.
- **A real, honestly-scoped bilingual slice**, not a framework nobody
  uses: the public landing page (`app/page.tsx`) and `/settings`'s new
  "Language" section are both genuinely translated end to end, with the
  settings page's own copy stating plainly that the rest of the app is
  still English-only. Every other page in the app is unaffected and
  renders exactly as before -- `getLocale()` defaults to `"en"` when no
  cookie is set, so nothing changes for anyone who hasn't touched the
  switcher.

## Why

The alternative -- pulling in `next-intl` and restructuring routing behind
`[locale]` -- solves a bigger problem than "there's currently zero i18n
capability, and it's blocking one small feature (announcement
translations)." A hand-rolled dictionary + fallback + cookie is the entire
mechanism content translations actually need to stop being blocked, is
fully auditable in this repo (same "no new dependency for logic this
simple" discipline as the PWA service worker and the HTTP load test
script), and is honest about not yet being a full solution: two real
pages are bilingual, not the whole app, and that boundary is stated
plainly in the UI itself (the settings copy) rather than only in a doc.

## Consequences

- 10 new unit tests (`lib/i18n/__tests__/{translate,locales}.test.ts`):
  English lookup, a real Spanish translation, the fallback-to-English
  path (exercised directly by removing then restoring a key at runtime,
  rather than leaving the real Spanish dictionary incomplete),
  interpolation with and without a matching param, and every real key in
  the Spanish dictionary having a non-empty value. 301 unit tests total
  (was 291).
- 1 new e2e test, and a genuinely real one: it clicks the Español
  button, asserts the heading and nav actually re-render in Spanish,
  reloads the page and asserts the choice persisted (the cookie), then
  clicks back to English and asserts the reversion. 27 e2e tests total
  (was 26) -- this is the one phase this session where a real
  authenticated-adjacent click-through WAS possible in this sandbox
  (the landing page needs no Supabase session), unlike almost everything
  else gated on a provisioned Supabase project.
- Content translations (the `announcement_translations` table ADR 0017
  deferred) are still not built -- the blocker (no i18n framework) is now
  gone, but building that table and wiring it into the announcements UI is
  its own separate phase, tracked as such rather than silently bundled in
  here.
- The rest of the app (every authenticated page, every admin page, every
  learner-facing flow) remains English-only; `<html lang="en">` in the
  root layout is unchanged and intentionally not locale-aware yet, since
  only two pages actually use `translate()` right now -- making `lang`
  dynamic before more of the app is translated would be less correct for
  assistive tech, not more.
