-- ============================================================================
-- Proves account deletion (20260922000018) actually works: a user who has
-- granted a role, created an organization, invited and accepted a member,
-- authored content, reviewed a capstone, granted a subscription, and been
-- logged to audit_log CAN be deleted from auth.users without a foreign key
-- violation -- and every one of those historical records survives with its
-- actor reference set to NULL, not deleted and not blocking. Meanwhile the
-- deleted user's own OWNED rows are still correctly gone via CASCADE, same
-- as always.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local');
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '11111111-1111-1111-1111-111111111111';
INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin') ON CONFLICT DO NOTHING;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ---- alice (admin) does a real thing in every one of the 8 fixed columns ---
CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- 1. user_roles.granted_by: alice grants bob 'instructor'.
DO $$ BEGIN PERFORM public.grant_platform_role('22222222-2222-2222-2222-222222222222', 'instructor'); END $$;

-- 2. organizations.created_by: alice creates an org.
DO $$ BEGIN
  INSERT INTO public.organizations (id, slug, name, created_by)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'deletion-test-org', 'Deletion Test Org', '11111111-1111-1111-1111-111111111111');
END $$;

-- 3/4. organization_invitations.invited_by + organization_members.invited_by:
-- alice invites bob, bob accepts.
DO $$ DECLARE v_token text; BEGIN
  SELECT public.create_organization_invitation('aaaaaaaa-0000-0000-0000-000000000001', 'bob@test.local', 'member') INTO v_token;
  PERFORM set_config('icorepen_test.invite_token', v_token, false);
END $$;

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$ BEGIN PERFORM public.accept_organization_invitation(current_setting('icorepen_test.invite_token')); END $$;

-- 5. learning_paths.created_by: alice authors a path.
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$ BEGIN
  INSERT INTO public.learning_paths (id, slug, title, created_by)
  VALUES ('cccccccc-0000-0000-0000-000000000003', 'deletion-test-path', 'Deletion Test Path', '11111111-1111-1111-1111-111111111111');
END $$;

-- 6. capstone_submissions.reviewer_id: alice reviews bob's capstone.
DO $$ BEGIN
  INSERT INTO public.capstones (id, slug, title, report_required, published)
  VALUES ('dddddddd-0000-0000-0000-000000000004', 'deletion-test-capstone', 'Deletion Test Capstone', true, true);
END $$;

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$ DECLARE v_submission_id uuid; BEGIN
  INSERT INTO public.capstone_submissions (capstone_id, user_id, report_content)
  VALUES ('dddddddd-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'Bob''s report.')
  RETURNING id INTO v_submission_id;
  PERFORM set_config('icorepen_test.submission_id', v_submission_id::text, false);
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$ BEGIN
  PERFORM public.review_capstone_submission(current_setting('icorepen_test.submission_id')::uuid, 'needs_revision', 'Try again.');
END $$;

-- 7. subscriptions.granted_by: alice grants bob a manual pro subscription.
DO $$ DECLARE v_pro_plan_id uuid; BEGIN
  SELECT id INTO v_pro_plan_id FROM public.plans WHERE slug = 'pro';
  PERFORM public.set_active_subscription('user', '22222222-2222-2222-2222-222222222222', v_pro_plan_id, 'active', 'manual');
END $$;

-- 8. audit_log.actor_id: alice's own actions above already logged plenty
-- (org creation isn't SQL-function-logged, but grant/invite/review/subscribe
-- all are); confirm at least one exists before deletion.
DO $$ DECLARE v_count int; BEGIN
  SELECT count(*) INTO v_count FROM public.audit_log WHERE actor_id = '11111111-1111-1111-1111-111111111111';
  IF v_count = 0 THEN RAISE EXCEPTION 'FAIL: fixture setup produced no audit_log rows for alice'; END IF;
END $$;

-- ============================================================================
-- Delete alice from auth.users -- this must succeed outright, not error.
-- (This is what the GoTrue Admin API's deleteUser() ultimately does at the
-- Postgres level; simulated directly here since GoTrue itself isn't part
-- of this local test harness -- see supabase/tests/bootstrap/0000_auth_stub.sql.)
-- ============================================================================
RESET ROLE;
DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111111';

-- ============================================================================
-- Every historical record survives with its actor reference nulled out --
-- not deleted, not blocking.
-- ============================================================================
DO $$
DECLARE v_role public.user_roles; v_org public.organizations; v_invite public.organization_invitations;
        v_member public.organization_members; v_path public.learning_paths;
        v_submission public.capstone_submissions; v_sub public.subscriptions;
        v_audit_count int;
BEGIN
  SELECT * INTO v_role FROM public.user_roles WHERE user_id = '22222222-2222-2222-2222-222222222222' AND role = 'instructor';
  IF NOT FOUND OR v_role.granted_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: user_roles.granted_by should be NULL after the granting admin is deleted, got %', v_role.granted_by;
  END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF NOT FOUND OR v_org.created_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: organizations.created_by should be NULL after the creator is deleted, got %', v_org.created_by;
  END IF;

  SELECT * INTO v_invite FROM public.organization_invitations WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF NOT FOUND OR v_invite.invited_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: organization_invitations.invited_by should be NULL, got %', v_invite.invited_by;
  END IF;

  SELECT * INTO v_member FROM public.organization_members
    WHERE organization_id = 'aaaaaaaa-0000-0000-0000-000000000001' AND user_id = '22222222-2222-2222-2222-222222222222';
  IF NOT FOUND OR v_member.invited_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: organization_members.invited_by should be NULL, got %', v_member.invited_by;
  END IF;

  SELECT * INTO v_path FROM public.learning_paths WHERE id = 'cccccccc-0000-0000-0000-000000000003';
  IF NOT FOUND OR v_path.created_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: learning_paths.created_by should be NULL, got %', v_path.created_by;
  END IF;

  SELECT * INTO v_submission FROM public.capstone_submissions WHERE id = current_setting('icorepen_test.submission_id')::uuid;
  IF NOT FOUND OR v_submission.reviewer_id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: capstone_submissions.reviewer_id should be NULL, got %', v_submission.reviewer_id;
  END IF;
  IF v_submission.status <> 'needs_revision' THEN
    RAISE EXCEPTION 'FAIL: the actual review outcome should survive the reviewer''s deletion, got %', v_submission.status;
  END IF;

  SELECT * INTO v_sub FROM public.subscriptions
    WHERE subject_type = 'user' AND subject_id = '22222222-2222-2222-2222-222222222222' AND status = 'active';
  IF NOT FOUND OR v_sub.granted_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: subscriptions.granted_by should be NULL, got %', v_sub.granted_by;
  END IF;

  SELECT count(*) INTO v_audit_count FROM public.audit_log WHERE actor_id IS NULL AND action IN ('user_role.granted', 'org.invitation.created', 'capstone.submission.reviewed', 'subscription.changed');
  IF v_audit_count < 4 THEN
    RAISE EXCEPTION 'FAIL: expected at least 4 surviving audit_log rows with actor_id nulled out, got %', v_audit_count;
  END IF;

  RAISE NOTICE 'PASS: deleting a user succeeds outright, and every historical record they touched survives with actor_id/created_by/invited_by/reviewer_id/granted_by set to NULL';
END $$;

-- ============================================================================
-- Alice's own OWNED rows are correctly gone (cascade still works).
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: alice''s profile should have been cascade-deleted'; END IF;

  SELECT count(*) INTO v_count FROM public.user_roles WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: alice''s own user_roles rows should have been cascade-deleted'; END IF;

  SELECT count(*) INTO v_count FROM public.organization_members WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: alice''s own organization_members row (team_owner) should have been cascade-deleted'; END IF;

  RAISE NOTICE 'PASS: the deleted user''s own owned rows are genuinely gone -- CASCADE still works correctly alongside the new SET NULL fixes';
END $$;

DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL ACCOUNT DELETION TESTS PASSED'
