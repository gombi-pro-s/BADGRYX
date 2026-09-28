-- ============================================================================
-- Announcement translations: this is the other half of the "Announcements,
-- translations" gap ADR 0017 deferred and the announcements migration's own
-- comment named explicitly -- the i18n framework (ADR 0025) now exists to
-- actually read one of these rows, so wiring it in is no longer inert
-- scaffolding with nothing consuming it.
--
-- Scope: one optional translation row per (announcement, locale). The base
-- announcements.title/body_markdown IS the English text (SUPPORTED_LOCALES'
-- DEFAULT_LOCALE) -- a translation row is only needed for a non-default
-- locale that has one, and the app falls back to the base row when none
-- exists (see lib/i18n/announcement-translation.ts's pickAnnouncementText()).
-- ============================================================================

CREATE TABLE public.announcement_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id uuid NOT NULL REFERENCES public.announcements (id) ON DELETE CASCADE,
  -- Kept in sync by hand with SUPPORTED_LOCALES in apps/web/src/lib/i18n/locales.ts
  -- ('en' is never actually stored here -- see the scope note above -- but is
  -- allowed rather than special-cased, since nothing breaks if it ever is).
  -- Adding a third locale means a migration to extend this CHECK too.
  locale text NOT NULL CHECK (locale IN ('en', 'es')),
  title text NOT NULL,
  body_markdown text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT announcement_translations_title_not_blank CHECK (length(btrim(title)) > 0),
  CONSTRAINT announcement_translations_body_not_blank CHECK (length(btrim(body_markdown)) > 0),
  CONSTRAINT announcement_translations_unique_locale UNIQUE (announcement_id, locale)
);

COMMENT ON TABLE public.announcement_translations IS
  'One optional row per (announcement, non-default locale). ON DELETE CASCADE '
  'from announcements: a translation with no announcement to translate is '
  'meaningless, same ownership-FK reasoning as announcements.organization_id.';

CREATE INDEX announcement_translations_announcement_id_idx
  ON public.announcement_translations (announcement_id);

CREATE TRIGGER announcement_translations_set_updated_at
  BEFORE UPDATE ON public.announcement_translations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.announcement_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_translations FORCE ROW LEVEL SECURITY;

-- Read/write mirror announcements_select/announcements_write exactly (see
-- 20260922000024_announcements.sql), applied through the parent row rather
-- than assumed via RLS-on-a-join: a translation is visible/writable by
-- exactly whoever can see/write the announcement it translates, no more and
-- no less -- the same explicit-EXISTS-with-full-predicate pattern
-- scan_files_select_own_or_staff/scan_findings_select_own_or_staff already
-- use for their own parent-scoped child tables.
CREATE POLICY announcement_translations_select ON public.announcement_translations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.announcements a
      WHERE a.id = announcement_translations.announcement_id
        AND (
          public.is_staff()
          OR (a.organization_id IS NOT NULL AND public.is_org_instructor(a.organization_id))
          OR (
            a.published
            AND (a.expires_at IS NULL OR a.expires_at > now())
            AND (a.organization_id IS NULL OR public.is_org_member(a.organization_id))
          )
        )
    )
  );

CREATE POLICY announcement_translations_write ON public.announcement_translations
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.announcements a
      WHERE a.id = announcement_translations.announcement_id
        AND (
          (a.organization_id IS NULL AND public.is_staff())
          OR (a.organization_id IS NOT NULL AND public.is_org_instructor(a.organization_id))
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.announcements a
      WHERE a.id = announcement_translations.announcement_id
        AND (
          (a.organization_id IS NULL AND public.is_staff())
          OR (a.organization_id IS NOT NULL AND public.is_org_instructor(a.organization_id))
        )
    )
  );
