-- ============================================================================
-- Proves announcements (20260922000024) are real: staff manage platform-wide
-- announcements, an org's own instructors+ manage that org's announcements,
-- a plain member can read published/non-expired announcements but cannot
-- write any, a member of an unrelated org cannot see or touch this org's
-- announcements even when published, an expired announcement is hidden from
-- an ordinary member but still visible to staff/instructors, and the
-- ownership vs. attribution FK behavior (ADR 0012) holds: deleting the org
-- cascades its announcements, deleting the author sets created_by null.
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

-- ============================================================================
-- 1. Staff can create a platform-wide announcement; a plain member cannot.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
INSERT INTO public.announcements (id, title, body_markdown, published, published_at)
VALUES ('c0000000-0000-0000-0000-000000000001', 'New CTF event live', 'Details...', true, now());
\echo 'PASS: staff created a platform-wide announcement'

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.announcements (title, body_markdown, published)
    VALUES ('Fake announcement', 'Body', true);
    RAISE EXCEPTION 'FAIL: a plain member created a platform-wide announcement';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a plain member cannot create a platform-wide announcement (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 2. A plain member of acme sees the published platform-wide announcement.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.announcements WHERE id = 'c0000000-0000-0000-0000-000000000001';
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected the member to see the published platform-wide announcement'; END IF;
  RAISE NOTICE 'PASS: a plain member sees a published platform-wide announcement';
END $$;

-- ============================================================================
-- 3. Carol (instructor of acme) can create an org-scoped announcement for
--    acme, but NOT for the unrelated globex org.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
INSERT INTO public.announcements (id, organization_id, title, body_markdown, published, published_at)
VALUES ('c0000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Lab maintenance tonight', 'Body', true, now());
\echo 'PASS: an org instructor created an announcement scoped to their own org'

DO $$
BEGIN
  BEGIN
    INSERT INTO public.announcements (organization_id, title, body_markdown, published)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'Not allowed', 'Body', true);
    RAISE EXCEPTION 'FAIL: carol created an announcement for an org she has no standing in';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an instructor cannot create an announcement for an unrelated org (%)', SQLSTATE;
  END;
END $$;

-- Carol also creates an unpublished draft, to prove drafts are visible to
-- her (instructor preview) but not to a plain member.
INSERT INTO public.announcements (id, organization_id, title, body_markdown, published)
VALUES ('c0000000-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'Draft notice', 'Body', false);

-- And an already-expired one, to prove expiry hides it from a plain member.
INSERT INTO public.announcements (id, organization_id, title, body_markdown, published, published_at, expires_at)
VALUES ('c0000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001', 'Old notice', 'Body', true, now() - interval '10 days', now() - interval '1 day');

DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.announcements
    WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 3 THEN RAISE EXCEPTION 'FAIL: expected carol (instructor) to see all 3 of acme''s announcements (published, draft, expired), got %', v_count; END IF;
  RAISE NOTICE 'PASS: an org instructor sees their org''s drafts and expired announcements too';
END $$;

-- ============================================================================
-- 4. Bob (plain member of acme) sees the published, non-expired org
--    announcement, but NOT the draft and NOT the expired one, and cannot
--    write any of them.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_visible_ids uuid[];
BEGIN
  SELECT array_agg(id) INTO v_visible_ids FROM public.announcements
    WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_visible_ids <> ARRAY['c0000000-0000-0000-0000-000000000002'::uuid] THEN
    RAISE EXCEPTION 'FAIL: expected bob to see only the published, non-expired org announcement, got %', v_visible_ids;
  END IF;
  RAISE NOTICE 'PASS: a plain member sees only published, non-expired org announcements';
END $$;

-- A plain member's UPDATE against a row RLS hides from them isn't a raised
-- error (RLS's USING clause just makes the row invisible to the UPDATE, so
-- it silently affects 0 rows) -- so this asserts the row count directly,
-- unlike the INSERT/WITH CHECK cases above where a real 42501 IS raised.
DO $$
DECLARE v_affected int; v_title text;
BEGIN
  UPDATE public.announcements SET title = 'Hijacked' WHERE id = 'c0000000-0000-0000-0000-000000000002';
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 0 THEN RAISE EXCEPTION 'FAIL: a plain member''s UPDATE affected % row(s) of an org announcement, expected 0', v_affected; END IF;

  SELECT title INTO v_title FROM public.announcements WHERE id = 'c0000000-0000-0000-0000-000000000002';
  IF v_title <> 'Lab maintenance tonight' THEN RAISE EXCEPTION 'FAIL: the announcement title changed despite the blocked update'; END IF;
  RAISE NOTICE 'PASS: a plain member''s UPDATE against an org announcement is RLS-blocked (0 rows affected, title unchanged)';
END $$;

-- ============================================================================
-- 5. Dave (team_owner of the unrelated globex org) cannot see acme's
--    announcements at all -- not the published one, not even by id.
-- ============================================================================
CALL test_act_as('44444444-4444-4444-4444-444444444444');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.announcements
    WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: an outsider saw acme''s org-scoped announcements, got %', v_count; END IF;
  RAISE NOTICE 'PASS: a member of an unrelated org cannot see this org''s announcements';
END $$;

-- ============================================================================
-- 6. Ownership vs. attribution (ADR 0012): deleting the org cascades its
--    announcements; deleting the author sets created_by null and the
--    announcement survives.
-- ============================================================================
RESET ROLE;
DO $$
DECLARE v_count int;
BEGIN
  DELETE FROM auth.users WHERE id = '33333333-3333-3333-3333-333333333333';
  SELECT count(*) INTO v_count FROM public.announcements
    WHERE id = 'c0000000-0000-0000-0000-000000000002' AND created_by IS NULL;
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected the announcement to survive with created_by set null after its author was deleted'; END IF;
  RAISE NOTICE 'PASS: deleting the author sets created_by null, the announcement survives (attribution FK)';
END $$;

DO $$
DECLARE v_count int;
BEGIN
  DELETE FROM public.organizations WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_count FROM public.announcements WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: expected all of acme''s announcements to be gone after the org was deleted, got %', v_count; END IF;
  RAISE NOTICE 'PASS: deleting the org cascades its announcements (ownership FK)';
END $$;

DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL ANNOUNCEMENTS TESTS PASSED'
