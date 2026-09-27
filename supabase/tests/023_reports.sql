-- ============================================================================
-- Proves reports (20260922000025) are real: only the owner can write their
-- own report, staff can read (moderation) but not write someone else's, a
-- different user cannot read or write it at all, and 'report' is a valid
-- mentor_context_type value a mentor_conversations row can actually use.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice-staff@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob-owner@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'carol-outsider@test.local');

INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ============================================================================
-- 1. Bob can create his own report.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
INSERT INTO public.reports (id, user_id, kind, title, content_markdown)
VALUES ('a0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'pentest_report', 'My first pentest report', 'Findings: ...');
\echo 'PASS: a user created their own report'

-- ============================================================================
-- 2. Bob cannot create a report attributed to someone else.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.reports (user_id, kind, title, content_markdown)
    VALUES ('11111111-1111-1111-1111-111111111111', 'pentest_report', 'Forged', 'Body');
    RAISE EXCEPTION 'FAIL: bob created a report attributed to alice';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a user cannot create a report attributed to someone else (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 3. Carol (an unrelated user) cannot see or edit bob's report.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_count int; v_affected int;
BEGIN
  SELECT count(*) INTO v_count FROM public.reports WHERE id = 'a0000000-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: an unrelated user saw someone else''s report'; END IF;
  RAISE NOTICE 'PASS: an unrelated user cannot see someone else''s report';

  UPDATE public.reports SET title = 'Hijacked' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 0 THEN RAISE EXCEPTION 'FAIL: an unrelated user updated someone else''s report'; END IF;
  RAISE NOTICE 'PASS: an unrelated user''s update against someone else''s report is RLS-blocked (0 rows affected)';
END $$;

-- ============================================================================
-- 4. Alice (staff) can read bob's report (moderation) but cannot write it.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_count int; v_affected int;
BEGIN
  SELECT count(*) INTO v_count FROM public.reports WHERE id = 'a0000000-0000-0000-0000-000000000001';
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: staff could not read a user''s report for moderation'; END IF;
  RAISE NOTICE 'PASS: staff can read any user''s report';

  UPDATE public.reports SET title = 'Hijacked by staff' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 0 THEN RAISE EXCEPTION 'FAIL: staff updated a user''s report directly'; END IF;
  RAISE NOTICE 'PASS: staff can read but not write another user''s report';
END $$;

-- ============================================================================
-- 5. Bob can update his own report.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
UPDATE public.reports SET content_markdown = 'Updated findings.' WHERE id = 'a0000000-0000-0000-0000-000000000001';
DO $$
DECLARE v_content text;
BEGIN
  SELECT content_markdown INTO v_content FROM public.reports WHERE id = 'a0000000-0000-0000-0000-000000000001';
  IF v_content <> 'Updated findings.' THEN RAISE EXCEPTION 'FAIL: bob''s own update to his report did not take effect'; END IF;
  RAISE NOTICE 'PASS: a user can update their own report';
END $$;

-- ============================================================================
-- 6. 'report' is a real mentor_context_type value -- a mentor_conversations
--    row can actually be created with it (proves the enum addition and the
--    existing FK/columns compose correctly, not just that the type exists
--    in isolation).
-- ============================================================================
INSERT INTO public.mentor_conversations (user_id, context_type, context_id)
VALUES ('22222222-2222-2222-2222-222222222222', 'report', 'a0000000-0000-0000-0000-000000000001');
\echo 'PASS: a mentor_conversations row can use context_type = report'

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL REPORTS TESTS PASSED'
