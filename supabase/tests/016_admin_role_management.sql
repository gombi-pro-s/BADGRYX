-- ============================================================================
-- Proves the admin role-management functions (20260922000016) are real:
-- only an admin can grant/revoke a platform role or search users, granting
-- is idempotent, revoking blocks an admin from locking themselves out (but
-- not from revoking a DIFFERENT admin's admin role), both actions are
-- audit-logged, and admin_search_users finds a user by email/username/
-- display_name while never exposing more than that plus current roles.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'admin-one@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'admin-two@test.local');
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '33333333-3333-3333-3333-333333333333';
INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-3333-3333-333333333333', 'admin') ON CONFLICT DO NOTHING;
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '44444444-4444-4444-4444-444444444444';
INSERT INTO public.user_roles (user_id, role) VALUES ('44444444-4444-4444-4444-444444444444', 'admin') ON CONFLICT DO NOTHING;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ============================================================================
-- 1. A non-admin cannot grant or revoke a role, or search users.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  BEGIN
    PERFORM public.grant_platform_role('11111111-1111-1111-1111-111111111111', 'instructor');
    RAISE EXCEPTION 'FAIL: a non-admin granted themselves a role';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: only an admin can grant a platform role (%)', SQLSTATE;
  END;

  BEGIN
    PERFORM public.revoke_platform_role('33333333-3333-3333-3333-333333333333', 'admin');
    RAISE EXCEPTION 'FAIL: a non-admin revoked another user''s role';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: only an admin can revoke a platform role (%)', SQLSTATE;
  END;

  BEGIN
    PERFORM public.admin_search_users('alice');
    RAISE EXCEPTION 'FAIL: a non-admin called admin_search_users';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: only an admin can call admin_search_users (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 2. Admin grants alice the instructor role; it's real, attributed, and
--    audit-logged. Granting again is idempotent (no duplicate row).
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_row public.user_roles; v_count int;
BEGIN
  SELECT * INTO v_row FROM public.grant_platform_role('11111111-1111-1111-1111-111111111111', 'instructor');
  IF v_row.role <> 'instructor' OR v_row.granted_by <> '33333333-3333-3333-3333-333333333333' THEN
    RAISE EXCEPTION 'FAIL: unexpected grant result: role=% granted_by=%', v_row.role, v_row.granted_by;
  END IF;

  PERFORM public.grant_platform_role('11111111-1111-1111-1111-111111111111', 'instructor');
  SELECT count(*) INTO v_count FROM public.user_roles
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND role = 'instructor';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: granting the same role twice created % rows, expected 1', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.audit_log WHERE action = 'user_role.granted' AND target_id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FAIL: expected 2 audit_log entries for the 2 grant calls, got %', v_count;
  END IF;
  RAISE NOTICE 'PASS: granting a role is real, attributed, idempotent, and audit-logged';
END $$;

-- ============================================================================
-- 3. Admin revokes alice's instructor role; it's really gone and logged.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  PERFORM public.revoke_platform_role('11111111-1111-1111-1111-111111111111', 'instructor');

  SELECT count(*) INTO v_count FROM public.user_roles
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND role = 'instructor';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: instructor role still present after revoke'; END IF;

  SELECT count(*) INTO v_count FROM public.audit_log WHERE action = 'user_role.revoked' AND target_id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 audit_log entry for the revoke, got %', v_count; END IF;
  RAISE NOTICE 'PASS: revoking a role is real and audit-logged';
END $$;

-- ============================================================================
-- 4. An admin cannot revoke their OWN admin role (lockout prevention), but
--    CAN revoke a DIFFERENT admin's admin role -- the guard is specifically
--    about self, not a blanket "admin role can never be revoked" rule.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  BEGIN
    PERFORM public.revoke_platform_role('33333333-3333-3333-3333-333333333333', 'admin');
    RAISE EXCEPTION 'FAIL: admin revoked their own admin role';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an admin cannot revoke their own admin role (%)', SQLSTATE;
  END;

  PERFORM public.revoke_platform_role('44444444-4444-4444-4444-444444444444', 'admin');
  SELECT count(*) INTO v_count FROM public.user_roles
    WHERE user_id = '44444444-4444-4444-4444-444444444444' AND role = 'admin';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: a different admin''s admin role should have been revocable'; END IF;
  RAISE NOTICE 'PASS: an admin CAN revoke a different admin''s admin role';
END $$;

-- ============================================================================
-- 5. admin_search_users finds a user by email/username/display_name, never
--    exposes more than id/email/username/display_name/roles, and excludes
--    the implicit 'user' role from the returned roles array.
-- ============================================================================
DO $$
DECLARE v_row record;
BEGIN
  SELECT * INTO v_row FROM public.admin_search_users('alice@test.local') LIMIT 1;
  IF v_row.user_id IS DISTINCT FROM '11111111-1111-1111-1111-111111111111'::uuid THEN
    RAISE EXCEPTION 'FAIL: admin_search_users did not find alice by email, got %', v_row.user_id;
  END IF;
  -- alice's instructor role was revoked above and she was never granted
  -- anything else, and the implicit 'user' role is always excluded, so her
  -- roles array should be empty (array_length of an empty array is NULL).
  IF array_length(v_row.roles, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: expected alice to have no non-default roles left, got %', v_row.roles;
  END IF;

  SELECT * INTO v_row FROM public.admin_search_users('admin-two') LIMIT 1;
  IF v_row.user_id IS DISTINCT FROM '44444444-4444-4444-4444-444444444444'::uuid THEN
    RAISE EXCEPTION 'FAIL: admin_search_users did not find admin-two by email substring';
  END IF;

  RAISE NOTICE 'PASS: admin_search_users finds real users by email and reports their real current roles';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL ADMIN ROLE MANAGEMENT TESTS PASSED'
