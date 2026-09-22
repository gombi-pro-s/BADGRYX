-- ============================================================================
-- Proves the org invitation lifecycle (20260922000017) now writes real,
-- organization-scoped audit_log rows: create_organization_invitation() and
-- accept_organization_invitation() both log, the owning org's admin can
-- read those entries via the existing org-scoped audit_log RLS branch
-- (not because they're a platform admin), and an admin of a DIFFERENT,
-- unrelated org cannot see them.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'carol@test.local');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- alice creates org A (auto team_owner); carol creates an unrelated org B.
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$ BEGIN
  INSERT INTO public.organizations (id, slug, name, created_by)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'audit-test-org-a', 'Audit Test Org A', '11111111-1111-1111-1111-111111111111');
END $$;

CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$ BEGIN
  INSERT INTO public.organizations (id, slug, name, created_by)
  VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'audit-test-org-b', 'Audit Test Org B', '33333333-3333-3333-3333-333333333333');
END $$;

-- ============================================================================
-- 1. create_organization_invitation() logs a real, org-scoped audit event.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_token text;
BEGIN
  SELECT public.create_organization_invitation('aaaaaaaa-0000-0000-0000-000000000001', 'bob@test.local', 'member') INTO v_token;
  PERFORM set_config('icorepen_test.invite_token', v_token, false);
END $$;

DO $$
DECLARE v_count int;
BEGIN
  -- alice (org A's team_owner) can read it via the org-scoped RLS branch --
  -- she is NOT a platform admin, so this only works if organization_id was
  -- actually populated on the row.
  SELECT count(*) INTO v_count FROM public.audit_log
    WHERE action = 'org.invitation.created' AND organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 org.invitation.created entry readable by org A''s own admin, got %', v_count;
  END IF;
  RAISE NOTICE 'PASS: create_organization_invitation() writes a real, org-scoped audit_log entry';
END $$;

-- ============================================================================
-- 2. Carol (admin of the DIFFERENT, unrelated org B) cannot see org A's
--    invitation audit trail -- not a platform admin either.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.audit_log WHERE action = 'org.invitation.created';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: an unrelated org''s admin can read org A''s audit trail (% rows)', v_count;
  END IF;
  RAISE NOTICE 'PASS: an unrelated org''s admin cannot read another org''s audit trail';
END $$;

-- ============================================================================
-- 3. accept_organization_invitation() also logs a real, org-scoped event.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_token text;
BEGIN
  v_token := current_setting('icorepen_test.invite_token');
  PERFORM public.accept_organization_invitation(v_token);
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.audit_log
    WHERE action = 'org.invitation.accepted' AND organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 org.invitation.accepted entry readable by org A''s own admin, got %', v_count;
  END IF;
  RAISE NOTICE 'PASS: accept_organization_invitation() writes a real, org-scoped audit_log entry';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL AUDIT LOG EXPANSION TESTS PASSED'
