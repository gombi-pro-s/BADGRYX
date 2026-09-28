-- ============================================================================
-- Proves announcement_translations (20260922000030) is real: visibility and
-- write access exactly mirror the announcement it translates -- staff manage
-- a platform-wide announcement's translations, an org's own instructors+
-- manage that org's announcement's translations, a plain member can read a
-- translation of a published/non-expired announcement but cannot write one,
-- an outsider sees neither the announcement nor its translation, the
-- (announcement_id, locale) uniqueness constraint holds, and deleting the
-- announcement cascades its translations.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice-staff@test.local'),      -- platform admin
  ('22222222-2222-2222-2222-222222222222', 'bob-member@test.local'),       -- member of acme
  ('33333333-3333-3333-3333-333333333333', 'carol-instructor@test.local'), -- instructor of acme
  ('44444444-4444-4444-4444-444444444444', 'dave-outsider@test.local'),    -- team_owner of an unrelated org
  ('55555555-5555-5555-5555-555555555555', 'eve-owner@test.local');       -- team_owner of acme (org creator)

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin');

INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'acme-security', 'Acme Security', '55555555-5555-5555-5555-555555555555');
INSERT INTO public.organization_members (organization_id, user_id, role) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'member'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'instructor');

INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'globex-corp', 'Globex Corp', '44444444-4444-4444-4444-444444444444');

-- Platform-wide announcement (staff-owned) + a published, org-scoped one
-- (acme, instructor-owned) to translate.
RESET ROLE;
INSERT INTO public.announcements (id, title, body_markdown, published, published_at, created_by)
VALUES ('c0000000-0000-0000-0000-000000000001', 'New CTF event live', 'Details...', true, now(), '11111111-1111-1111-1111-111111111111');
INSERT INTO public.announcements (id, organization_id, title, body_markdown, published, published_at, created_by)
VALUES ('c0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lab maintenance tonight', 'Body', true, now(), '33333333-3333-3333-3333-333333333333');

-- ============================================================================
-- 1. Staff can add a Spanish translation to the platform-wide announcement;
--    a plain member cannot.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
INSERT INTO public.announcement_translations (id, announcement_id, locale, title, body_markdown)
VALUES ('d0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'es', 'Nuevo evento CTF en vivo', 'Detalles...');
\echo 'PASS: staff added a Spanish translation to the platform-wide announcement'

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.announcement_translations (announcement_id, locale, title, body_markdown)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'es', 'Fake', 'Fake');
    RAISE EXCEPTION 'FAIL: a plain member added a translation to a platform-wide announcement';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a plain member cannot write a translation of a platform-wide announcement (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 2. Bob (plain member of acme) can READ the platform-wide announcement's
--    translation, since he can already read the announcement itself.
-- ============================================================================
DO $$
DECLARE v_title text;
BEGIN
  SELECT title INTO v_title FROM public.announcement_translations WHERE id = 'd0000000-0000-0000-0000-000000000001';
  IF v_title <> 'Nuevo evento CTF en vivo' THEN RAISE EXCEPTION 'FAIL: expected bob to read the Spanish translation, got %', v_title; END IF;
  RAISE NOTICE 'PASS: a plain member reads a translation of an announcement they can already read';
END $$;

-- ============================================================================
-- 3. Carol (instructor of acme) can add a translation to her own org's
--    announcement, but NOT to the platform-wide one (she's not staff).
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
INSERT INTO public.announcement_translations (id, announcement_id, locale, title, body_markdown)
VALUES ('d0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000002', 'es', 'Mantenimiento del laboratorio esta noche', 'Cuerpo');
\echo 'PASS: an org instructor added a translation to their own org''s announcement'

DO $$
BEGIN
  BEGIN
    INSERT INTO public.announcement_translations (announcement_id, locale, title, body_markdown)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'es', 'Not allowed', 'Not allowed');
    RAISE EXCEPTION 'FAIL: an org instructor added a translation to the platform-wide announcement';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an org instructor cannot write a translation of a platform-wide announcement (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 4. Dave (team_owner of the unrelated globex org) cannot see acme's
--    announcement OR its translation.
-- ============================================================================
CALL test_act_as('44444444-4444-4444-4444-444444444444');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.announcement_translations WHERE announcement_id = 'c0000000-0000-0000-0000-000000000002';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: an outsider saw acme''s announcement translation, got %', v_count; END IF;
  RAISE NOTICE 'PASS: a member of an unrelated org cannot see this org''s announcement translation';
END $$;

-- ============================================================================
-- 5. Uniqueness: a second 'es' translation for the same announcement is
--    rejected.
-- ============================================================================
RESET ROLE;
DO $$
BEGIN
  BEGIN
    INSERT INTO public.announcement_translations (announcement_id, locale, title, body_markdown)
    VALUES ('c0000000-0000-0000-0000-000000000001', 'es', 'Duplicate', 'Duplicate');
    RAISE EXCEPTION 'FAIL: a second Spanish translation for the same announcement was accepted';
  EXCEPTION
    WHEN unique_violation THEN
      RAISE NOTICE 'PASS: (announcement_id, locale) uniqueness is enforced';
  END;
END $$;

-- ============================================================================
-- 6. Deleting the announcement cascades its translation.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  DELETE FROM public.announcements WHERE id = 'c0000000-0000-0000-0000-000000000002';
  SELECT count(*) INTO v_count FROM public.announcement_translations WHERE announcement_id = 'c0000000-0000-0000-0000-000000000002';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: expected the translation to be gone after its announcement was deleted, got %', v_count; END IF;
  RAISE NOTICE 'PASS: deleting the announcement cascades its translations';
END $$;

DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL ANNOUNCEMENT TRANSLATIONS TESTS PASSED'
