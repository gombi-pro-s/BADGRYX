# ADR 0017: Announcements — built now; translations deferred, not forgotten

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` grouped "Announcements, translations" as one
unbuilt line under Content authoring. They are not actually one feature:

- **Announcements** is a real, self-contained content type: a notice an
  admin or instructor posts, that learners see. It needs no other
  infrastructure to be genuinely useful today.
- **Translations** means alternate-locale versions of existing content
  (lessons, announcements, whatever). Rendering one requires an i18n
  framework — locale routing, a language switcher, a place in the request
  path that picks a locale — and `RELEASE_CHECKLIST.md`'s "Application
  foundation" section already tracks that framework as a separate,
  not-started item. Building a `*_translations` table today, with nothing
  in the app that ever reads a non-default locale, would be schema for a
  feature no code path can reach — exactly the kind of inert scaffolding
  this project's no-placeholder-functionality rule exists to prevent.

## Decision

Build announcements now; leave translations tracked under the i18n
framework item, where it actually belongs.

- `announcements` (`20260922000024_announcements.sql`): `organization_id`
  nullable — NULL means platform-wide (staff-authored), non-null means
  scoped to that org's own members (authored by one of its
  instructor/team_owner/org_admin). This mirrors the ownership vs.
  attribution FK convention (ADR 0012): `organization_id` is `ON DELETE
  CASCADE` (an announcement scoped to a deleted org is meaningless),
  `created_by` is `ON DELETE SET NULL` (the notice itself should survive
  its author's account being deleted).
- A new RLS helper, `is_org_instructor(org_id)`, mirrors the existing
  `is_org_admin(org_id)` (`20260921000003_organizations_teams.sql`) but
  also includes the `instructor` role — "post a notice to my class" is
  exactly the authority an instructor should have without needing
  `team_owner`/`org_admin`'s membership-management authority.
- Read policy: staff see every announcement everywhere (moderation); an
  org's own instructors+ see that org's drafts and expired notices too (so
  they can preview before publishing); everyone else sees only published,
  non-expired announcements that are platform-wide or scoped to an org they
  belong to.
- Write policy: staff manage platform-wide announcements; an org's own
  instructors+ manage that org's announcements. Same shape as
  `learning_paths_staff_write` and the org-management policies — no new
  enforcement pattern invented.
- No SECURITY DEFINER function: like every other content-authoring table
  (ADR 0004), plain RLS is the sole write gate. There's nothing here to
  grade or transition through states.
- Unlike every other content type in this CMS, announcements really can be
  **deleted**, not just unpublished. Nothing else in the schema references
  an announcement's id — no learner progress, no evidence, nothing graded
  — so a delete can never orphan a reference the way deleting a lesson or
  lab could. A stale notice is meant to go away.
- Two authoring surfaces, same table: `/admin/announcements` (platform-
  wide, `requireAdmin()`) and `/orgs/[orgId]/announcements`
  (org-scoped, `requireOrgInstructor()`). Both call the same RLS-gated
  table through nearly identical actions — the surfaces differ only in
  which `organization_id` they write and how they're gated at the app
  layer, exactly the "app-layer gate is UX-fast-fail, RLS is the real
  check" split already documented at the top of `middleware.ts`.
- `/dashboard` shows up to 5 active announcements (published, not expired)
  above the existing skill-progress cards. The query filters
  `published = true` and the expiry window explicitly rather than relying
  on RLS's staff/instructor-preview branches to exclude drafts — a staff
  member or instructor viewing their own dashboard should see the same
  "what's actually live" banner a learner does, not their own unpublished
  drafts leaking into their personal dashboard.

## Why

Splitting the checklist line into "buildable now" and "genuinely blocked
on a separate, already-tracked gap" is the same judgment call this project
has made repeatedly (e.g. MFA's `getAuthenticatorAssuranceLevel()` needing
no new schema, or scoping bulk import/export to learning paths in ADR
0016) — build the real thing, and say plainly what's still missing and
why, rather than either skipping the whole line or building a translations
table nothing can render.

## Consequences

- New SQL regression test (`supabase/tests/022_announcements.sql`, 11
  assertions): staff-only platform-wide writes, an instructor's org-scoped
  write succeeding for their own org and failing for an unrelated one, a
  plain member's read visibility (published/non-expired only) vs. an
  instructor's preview visibility (drafts and expired too), an outsider
  seeing nothing, a blocked UPDATE affecting 0 rows (not a raised
  exception — RLS's `USING` clause on an existing row silently excludes it
  from the affected set, unlike an `INSERT`'s `WITH CHECK` failure, which
  does raise `42501`), and both FK behaviors (cascade on org deletion,
  set-null on author deletion).
- Verified by the full SQL regression suite (22 files, all passing),
  `tsc --noEmit`, ESLint (including this project's `react-hooks/purity`
  rule, which flagged a bare `Date.now()` in a Server Component render
  path — fixed by using `new Date().getTime()` instead, matching what
  already passed lint elsewhere in this codebase), a clean production
  build (all 4 new routes present), and 1 new e2e test. A real authenticated
  click-through (post an announcement, see it land on another user's
  dashboard) needs a provisioned Supabase project, the same limitation as
  every other admin-CMS or org flow in this sandbox.
- Translations remain explicitly not started, tracked under "i18n
  framework in place" in `RELEASE_CHECKLIST.md`'s Application foundation
  section — not silently dropped, not half-built as inert schema.
