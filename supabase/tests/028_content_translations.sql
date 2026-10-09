-- ============================================================================
-- Proves learning_path_translations/lesson_translations (20260922000032) are
-- real: visibility and write access exactly mirror the path/lesson each
-- translates -- staff can write a translation, a plain user cannot, a plain
-- user CAN read a translation of published content, nobody can read a
-- translation of unpublished content unless staff, the (parent_id, locale)
-- uniqueness constraint holds, and deleting the parent cascades its
-- translation.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice-staff@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob-member@test.local');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin');

INSERT INTO public.learning_paths (id, slug, title, description, published) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'sql-injection', 'SQL Injection', 'Learn SQLi.', true),
  ('a0000000-0000-0000-0000-000000000002', 'draft-path', 'Draft Path', 'Not out yet.', false);
INSERT INTO public.modules (id, path_id, slug, title, published) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'intro', 'Intro', true);
INSERT INTO public.lessons (id, module_id, slug, title, content_markdown, published) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'what-is-sqli', 'What is SQLi?', 'Body text.', true);

-- ============================================================================
-- 1. Staff can add a Spanish translation to a published path; a plain user
--    cannot.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
INSERT INTO public.learning_path_translations (id, path_id, locale, title, description)
VALUES ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'es', 'Inyección SQL', 'Aprende inyección SQL.');
\echo 'PASS: staff added a Spanish translation to a published path'

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.learning_path_translations (path_id, locale, title, description)
    VALUES ('a0000000-0000-0000-0000-000000000001', 'es', 'Fake', 'Fake');
    RAISE EXCEPTION 'FAIL: a plain user added a translation to a learning path';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: a plain user cannot write a learning path translation (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 2. The same plain user CAN read that translation, since the path is published.
-- ============================================================================
DO $$
DECLARE v_title text;
BEGIN
  SELECT title INTO v_title FROM public.learning_path_translations WHERE id = 'd0000000-0000-0000-0000-000000000001';
  IF v_title <> 'Inyección SQL' THEN RAISE EXCEPTION 'FAIL: expected to read the Spanish path title, got %', v_title; END IF;
  RAISE NOTICE 'PASS: a plain user reads a translation of a published path';
END $$;

-- ============================================================================
-- 3. A translation of an UNPUBLISHED path is invisible to a plain user.
-- ============================================================================
RESET ROLE;
INSERT INTO public.learning_path_translations (id, path_id, locale, title)
VALUES ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'es', 'Borrador');
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.learning_path_translations WHERE path_id = 'a0000000-0000-0000-0000-000000000002';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: a plain user saw a draft path''s translation, got %', v_count; END IF;
  RAISE NOTICE 'PASS: a plain user cannot see a translation of an unpublished path';
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.learning_path_translations WHERE path_id = 'a0000000-0000-0000-0000-000000000002';
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: staff could not see a draft path''s translation, got %', v_count; END IF;
  RAISE NOTICE 'PASS: staff can see a translation of an unpublished path';
END $$;

-- ============================================================================
-- 4. Uniqueness: a second 'es' translation for the same path is rejected.
-- ============================================================================
RESET ROLE;
DO $$
BEGIN
  BEGIN
    INSERT INTO public.learning_path_translations (path_id, locale, title)
    VALUES ('a0000000-0000-0000-0000-000000000001', 'es', 'Duplicate');
    RAISE EXCEPTION 'FAIL: a second Spanish translation for the same path was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: (path_id, locale) uniqueness is enforced';
  END;
END $$;

-- ============================================================================
-- 5. Deleting the path cascades its translation.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  DELETE FROM public.learning_paths WHERE id = 'a0000000-0000-0000-0000-000000000002';
  SELECT count(*) INTO v_count FROM public.learning_path_translations WHERE path_id = 'a0000000-0000-0000-0000-000000000002';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: expected the translation to be gone after its path was deleted, got %', v_count; END IF;
  RAISE NOTICE 'PASS: deleting a learning path cascades its translations';
END $$;

-- ============================================================================
-- 6. Lesson translations: same staff-write/published-read shape, proven
--    once (the RLS policies are identical in structure to the path ones
--    above, just scoped through lessons instead).
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
INSERT INTO public.lesson_translations (id, lesson_id, locale, title, content_markdown)
VALUES ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'es', '¿Qué es la inyección SQL?', 'Texto del cuerpo.');
\echo 'PASS: staff added a Spanish translation to a published lesson'

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_title text;
BEGIN
  SELECT title INTO v_title FROM public.lesson_translations WHERE id = 'e0000000-0000-0000-0000-000000000001';
  IF v_title <> '¿Qué es la inyección SQL?' THEN RAISE EXCEPTION 'FAIL: expected to read the Spanish lesson title, got %', v_title; END IF;
  RAISE NOTICE 'PASS: a plain user reads a translation of a published lesson';

  BEGIN
    INSERT INTO public.lesson_translations (lesson_id, locale, title, content_markdown)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'es', 'Fake', 'Fake');
    RAISE EXCEPTION 'FAIL: a plain user added a translation to a lesson';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: a plain user cannot write a lesson translation (%)', SQLSTATE;
  END;
END $$;

RESET ROLE;
DO $$
DECLARE v_count int;
BEGIN
  DELETE FROM public.lessons WHERE id = 'c0000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_count FROM public.lesson_translations WHERE lesson_id = 'c0000000-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: expected the translation to be gone after its lesson was deleted, got %', v_count; END IF;
  RAISE NOTICE 'PASS: deleting a lesson cascades its translations';
END $$;

DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL CONTENT TRANSLATIONS TESTS PASSED'
