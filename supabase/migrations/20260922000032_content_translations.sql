-- ============================================================================
-- Learning path and lesson translations: the other half of "content
-- translations for other user-authored content types beyond announcements
-- (paths, lessons, etc.)" -- named as a real, deliberately deferred gap in
-- RELEASE_CHECKLIST.md/README.md ever since announcement_translations
-- (20260922000030) shipped only announcements.
--
-- Same design as announcement_translations, applied to the two content
-- tables where translating the actual learning material matters most: a
-- path's own title/description (what a learner sees browsing /learn), and
-- a lesson's title/content_markdown (what a learner actually reads).
-- Modules are intentionally left out -- a module only ever has a title,
-- no body text, and the admin UI for modules doesn't even have an edit
-- form (see ADR 0055); a title-only translation isn't worth a third table
-- for the same reason an edit form for modules wasn't built.
--
-- Scope, same as announcement_translations: one optional translation row
-- per (content row, locale). The base row IS the English text
-- (SUPPORTED_LOCALES' DEFAULT_LOCALE) -- a translation row only exists for
-- a non-default locale that has one, and the app falls back to the base
-- row when none exists.
-- ============================================================================

CREATE TABLE public.learning_path_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path_id uuid NOT NULL REFERENCES public.learning_paths (id) ON DELETE CASCADE,
  -- Kept in sync by hand with SUPPORTED_LOCALES in apps/web/src/lib/i18n/locales.ts.
  locale text NOT NULL CHECK (locale IN ('en', 'es')),
  title text NOT NULL,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT learning_path_translations_title_not_blank CHECK (length(btrim(title)) > 0),
  CONSTRAINT learning_path_translations_unique_locale UNIQUE (path_id, locale)
);

COMMENT ON TABLE public.learning_path_translations IS
  'One optional row per (learning path, non-default locale). ON DELETE CASCADE '
  'from learning_paths: a translation with no path to translate is meaningless.';

CREATE INDEX learning_path_translations_path_id_idx
  ON public.learning_path_translations (path_id);

CREATE TRIGGER learning_path_translations_set_updated_at
  BEFORE UPDATE ON public.learning_path_translations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.learning_path_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_path_translations FORCE ROW LEVEL SECURITY;

-- Mirrors learning_paths_select_published_or_staff / learning_paths_staff_write
-- exactly, applied through the parent row -- a translation is visible/writable
-- by exactly whoever can see/write the path it translates, no more and no less.
CREATE POLICY learning_path_translations_select ON public.learning_path_translations
  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.learning_paths p
      WHERE p.id = learning_path_translations.path_id AND (p.published OR public.is_staff())
    )
  );

CREATE POLICY learning_path_translations_write ON public.learning_path_translations
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.learning_paths p WHERE p.id = learning_path_translations.path_id AND public.is_staff())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.learning_paths p WHERE p.id = learning_path_translations.path_id AND public.is_staff())
  );

CREATE TABLE public.lesson_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES public.lessons (id) ON DELETE CASCADE,
  locale text NOT NULL CHECK (locale IN ('en', 'es')),
  title text NOT NULL,
  content_markdown text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lesson_translations_title_not_blank CHECK (length(btrim(title)) > 0),
  CONSTRAINT lesson_translations_content_not_blank CHECK (length(btrim(content_markdown)) > 0),
  CONSTRAINT lesson_translations_unique_locale UNIQUE (lesson_id, locale)
);

COMMENT ON TABLE public.lesson_translations IS
  'One optional row per (lesson, non-default locale). ON DELETE CASCADE from '
  'lessons: a translation with no lesson to translate is meaningless.';

CREATE INDEX lesson_translations_lesson_id_idx ON public.lesson_translations (lesson_id);

CREATE TRIGGER lesson_translations_set_updated_at
  BEFORE UPDATE ON public.lesson_translations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.lesson_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_translations FORCE ROW LEVEL SECURITY;

CREATE POLICY lesson_translations_select ON public.lesson_translations
  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.lessons l
      WHERE l.id = lesson_translations.lesson_id AND (l.published OR public.is_staff())
    )
  );

CREATE POLICY lesson_translations_write ON public.lesson_translations
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.lessons l WHERE l.id = lesson_translations.lesson_id AND public.is_staff())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.lessons l WHERE l.id = lesson_translations.lesson_id AND public.is_staff())
  );
