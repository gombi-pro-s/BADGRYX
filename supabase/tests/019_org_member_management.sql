-- ============================================================================
-- Proves the org member-management functions (20260922000019) are real:
-- only an org admin/team owner can change a member's role or remove someone
-- else, a plain member can remove themselves (leave), neither can demote or
-- remove the organization's last team_owner, both actions are audit-logged,
-- and an org_admin from an unrelated organization has no authority here.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),   -- team_owner of acme
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),     -- member of acme
  ('33333333-3333-3333-3333-333333333333', 'carol@test.local'),   -- org_admin of acme
  ('44444444-4444-4444-4444-444444444444', 'ollie@test.local');   -- team_owner of an unrelated org

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'acme-security', 'Acme Security', '11111111-1111-1111-1111-111111111111');
INSERT INTO public.organization_members (organization_id, user_id, role) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'member'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', 'org_admin');

INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'globex-corp', 'Globex Corp', '44444444-4444-4444-4444-444444444444');

CREATE TEMP TABLE t_ids AS SELECT
  (SELECT id FROM public.organization_members WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     AND user_id = '11111111-1111-1111-1111-111111111111') AS alice_member_id,
  (SELECT id FROM public.organization_members WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     AND user_id = '22222222-2222-2222-2222-222222222222') AS bob_member_id,
  (SELECT id FROM public.organization_members WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001'
     AND user_id = '33333333-3333-3333-3333-333333333333') AS carol_member_id;
GRANT SELECT, UPDATE ON t_ids TO authenticated;

-- ============================================================================
-- 1. A plain member cannot change anyone's role or remove someone else, but
--    CAN remove (leave) themselves.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_carol_id uuid; v_bob_id uuid;
BEGIN
  SELECT carol_member_id INTO v_carol_id FROM t_ids;
  SELECT bob_member_id INTO v_bob_id FROM t_ids;

  BEGIN
    PERFORM public.update_organization_member_role('aaaaaaaa-0000-0000-0000-000000000001', v_carol_id, 'member');
    RAISE EXCEPTION 'FAIL: a plain member changed another member''s role';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: only an org admin/team owner can change a member''s role (%)', SQLSTATE;
  END;

  BEGIN
    PERFORM public.remove_organization_member('aaaaaaaa-0000-0000-0000-000000000001', v_carol_id);
    RAISE EXCEPTION 'FAIL: a plain member removed a different member';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a plain member cannot remove someone else (%)', SQLSTATE;
  END;

  PERFORM public.remove_organization_member('aaaaaaaa-0000-0000-0000-000000000001', v_bob_id);
  RAISE NOTICE 'PASS: a member can remove (leave) themselves';
END $$;

-- Re-add bob as a member for the remaining tests (superuser fixture insert,
-- exactly as accept_organization_invitation would via the real invite flow).
RESET ROLE;
INSERT INTO public.organization_members (organization_id, user_id, role)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'member')
RETURNING id;
UPDATE t_ids SET bob_member_id = (
  SELECT id FROM public.organization_members WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001'
    AND user_id = '22222222-2222-2222-2222-222222222222'
);

-- ============================================================================
-- 2. An org_admin from an UNRELATED org has no authority over acme's members.
-- ============================================================================
CALL test_act_as('44444444-4444-4444-4444-444444444444');
DO $$
DECLARE v_bob_id uuid;
BEGIN
  SELECT bob_member_id INTO v_bob_id FROM t_ids;
  BEGIN
    PERFORM public.update_organization_member_role('aaaaaaaa-0000-0000-0000-000000000001', v_bob_id, 'instructor');
    RAISE EXCEPTION 'FAIL: an outsider org owner changed acme''s member role';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an outsider org owner has no authority over a different org''s members (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 3. carol (org_admin) promotes bob to instructor -- real, attributed via
--    audit_log, and reflected in the table.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_bob_id uuid; v_row public.organization_members; v_count int;
BEGIN
  SELECT bob_member_id INTO v_bob_id FROM t_ids;
  SELECT * INTO v_row FROM public.update_organization_member_role('aaaaaaaa-0000-0000-0000-000000000001', v_bob_id, 'instructor');
  IF v_row.role <> 'instructor' THEN
    RAISE EXCEPTION 'FAIL: expected bob''s role to be instructor, got %', v_row.role;
  END IF;

  SELECT count(*) INTO v_count FROM public.audit_log
    WHERE action = 'org.member.role_changed' AND target_id = v_bob_id::text;
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 audit_log entry for the role change, got %', v_count; END IF;
  RAISE NOTICE 'PASS: an org admin can change a member''s role, and it is audit-logged';
END $$;

-- ============================================================================
-- 4. Nobody can demote or remove the last team_owner (alice) -- not carol
--    (org_admin), and not even alice herself.
-- ============================================================================
DO $$
DECLARE v_alice_id uuid;
BEGIN
  SELECT alice_member_id INTO v_alice_id FROM t_ids;

  BEGIN
    PERFORM public.update_organization_member_role('aaaaaaaa-0000-0000-0000-000000000001', v_alice_id, 'org_admin');
    RAISE EXCEPTION 'FAIL: the last team_owner was demoted';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: the last team_owner cannot be demoted (%)', SQLSTATE;
  END;

  BEGIN
    PERFORM public.remove_organization_member('aaaaaaaa-0000-0000-0000-000000000001', v_alice_id);
    RAISE EXCEPTION 'FAIL: the last team_owner was removed';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: the last team_owner cannot be removed (%)', SQLSTATE;
  END;
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_alice_id uuid;
BEGIN
  SELECT alice_member_id INTO v_alice_id FROM t_ids;
  BEGIN
    PERFORM public.remove_organization_member('aaaaaaaa-0000-0000-0000-000000000001', v_alice_id);
    RAISE EXCEPTION 'FAIL: alice removed herself as the last team_owner';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: the last team_owner cannot even remove themselves (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 5. Promoting a second team_owner, THEN demoting/removing the first one,
--    works fine -- the guard is about the count, not a specific person.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_bob_id uuid; v_alice_id uuid; v_row public.organization_members; v_count int;
BEGIN
  SELECT bob_member_id, alice_member_id INTO v_bob_id, v_alice_id FROM t_ids;

  PERFORM public.update_organization_member_role('aaaaaaaa-0000-0000-0000-000000000001', v_bob_id, 'team_owner');

  SELECT * INTO v_row FROM public.update_organization_member_role('aaaaaaaa-0000-0000-0000-000000000001', v_alice_id, 'member');
  IF v_row.role <> 'member' THEN
    RAISE EXCEPTION 'FAIL: alice should have been demoted now that bob is also a team_owner, got %', v_row.role;
  END IF;
  RAISE NOTICE 'PASS: demoting a team_owner succeeds once a second team_owner exists';

  PERFORM public.remove_organization_member('aaaaaaaa-0000-0000-0000-000000000001', v_alice_id);
  SELECT count(*) INTO v_count FROM public.organization_members WHERE id = v_alice_id;
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: alice''s membership should be gone after removal'; END IF;

  SELECT count(*) INTO v_count FROM public.audit_log WHERE action = 'org.member.removed' AND target_id = v_alice_id::text;
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 audit_log entry for the removal, got %', v_count; END IF;
  RAISE NOTICE 'PASS: removing a non-last team_owner succeeds and is audit-logged';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL ORG MEMBER MANAGEMENT TESTS PASSED'
