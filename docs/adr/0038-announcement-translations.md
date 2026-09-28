# ADR 0038: Announcement translations

## Status

Accepted.

## Context

ADR 0017 (announcements) deliberately deferred translations, and its own
migration comment named the reason explicitly: no i18n framework existed
yet to ever read a translated string, so a translations table would have
been inert scaffolding with nothing consuming it. ADR 0025 built that
framework (a cookie-based locale, `translate()`, a real English/Spanish
slice on the landing page and `/settings`). This ADR is the deferred half
now that there's something to wire it into.

## Decision

- `announcement_translations` (migration
  `20260922000030_announcement_translations.sql`): one optional row per
  `(announcement_id, locale)`, `UNIQUE` constraint, `ON DELETE CASCADE`
  from `announcements`. `locale` is `CHECK`-constrained to `('en', 'es')`
  -- kept in sync by hand with `SUPPORTED_LOCALES`
  (`lib/i18n/locales.ts`); adding a third locale needs a migration here
  too, an explicit, small cost rather than an open-ended `text` column.
- RLS mirrors `announcements_select`/`announcements_write` exactly,
  applied through the parent row via an explicit `EXISTS` with the full
  visibility predicate repeated (the same pattern
  `scan_files_select_own_or_staff`/`scan_findings_select_own_or_staff`
  already use for their own parent-scoped child tables) -- a translation
  is visible/writable by exactly whoever can see/write the announcement
  it translates, no more and no less.
- The base `announcements.title`/`body_markdown` IS the English
  (`DEFAULT_LOCALE`) text; a translation row is only needed for a
  non-default locale that has one. `lib/i18n/announcement-translation.ts`'s
  `pickAnnouncementText(base, translations, locale)` returns the base text
  for the default locale (even if a translation row somehow exists) and
  the matching translation otherwise, falling back to the base text when
  none exists -- pure, unit-tested, no I/O.
- Admin (`/admin/announcements`) and org-scoped
  (`/orgs/[orgId]/announcements`) create/edit forms gained an optional
  "Spanish translation" fieldset (title + body). Both fields blank means
  "no translation" (deletes any existing row); both filled upserts one.
  Only Spanish exists as a field pair today, matching
  `SUPPORTED_LOCALES`'s only non-default locale -- a third locale means a
  new field pair, not a generalized N-locale form, matching the CHECK
  constraint's own scope.
- `/dashboard` now calls `getLocale()` and fetches each shown
  announcement's translations in one follow-up query, then renders
  `pickAnnouncementText()`'s result instead of the raw row.

## Why

- **Mirroring the parent's RLS predicate directly**, rather than assuming
  RLS-inside-a-subquery transparently does the right thing, keeps this
  table's security model as explicit and auditable as every other
  parent-scoped child table in this schema.
- **A curated two-locale CHECK constraint** is real defense-in-depth for
  a small, deliberately-scoped set, not over-engineering for a locale
  list that changes rarely and needs an app-level dictionary
  (`messages/<locale>.ts`) anyway when it does.
- **The base row IS the default locale's text** avoids ever needing an
  `'en'` translation row for the common case -- one query fetches
  everything a default-locale visitor needs, and a second, narrow query
  (by exactly the shown announcement ids) covers everyone else.

## Consequences

- 8 new SQL regression assertions (`026_announcement_translations.sql`,
  run for real against a local Postgres cluster started in this sandbox
  via `scripts/run-sql-tests.sh`): staff write a platform-wide
  announcement's translation and a plain member cannot; a plain member
  reads a translation of an announcement they can already read; an org
  instructor writes their own org's translation but not the
  platform-wide one; an outsider sees neither; `(announcement_id,
  locale)` uniqueness is enforced; deleting the announcement cascades its
  translation. 191 SQL regression assertions total across 26 files -- a
  direct recount (`grep -c "PASS:"` across every `supabase/tests/*.sql`
  file) rather than trusting the prior hand-carried running total, which
  had drifted a few assertions out of sync with the actual files.
- +8 unit tests (4 pure `pickAnnouncementText()` cases, 4 component tests
  proving the Spanish fields round-trip through `FormData` and clear
  correctly) -- 316 unit tests total (was 308).
- `tsc --noEmit`, ESLint, `next build`, and all 30 e2e tests stay clean/
  passing (no new e2e case: exercising the dashboard's actual translated
  render needs a real authenticated session against a real Supabase
  project, the same "needs a provisioned environment this sandbox
  doesn't have" limitation as every other authenticated click-through in
  `RELEASE_CHECKLIST.md`).
- Closes the "Content translations" gap `RELEASE_CHECKLIST.md` and
  ADR 0017/0025 named -- for announcements specifically; other
  user-authored content types (paths, lessons, etc.) remain untranslated,
  a separate, larger decision not bundled into this one.
