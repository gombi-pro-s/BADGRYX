-- ============================================================================
-- Proves the org-instructor visibility RLS extension (20260922000012) and the
-- invitation lifecycle functions actually work, not just apply cleanly:
--
--  1. An instructor of alice's org CAN see her real quiz/ctf/capstone/
--     investigation results (via the real grading RPCs / real insert paths,
--     not fixture rows planted with correct=true).
--  2. An instructor of a DIFFERENT, unrelated org CANNOT see them.
--  3. Alice herself and a plain member of her own org (non-instructor) still
--     cannot see each other's results (this policy only ever widens
--     visibility for instructor/team_owner/org_admin roles).
--  4. create_organization_invitation()/accept_organization_invitation():
--     happy path, wrong-email rejection, double-accept rejection, expired
--     rejection, revoked rejection, and seat_limit enforcement.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---- Fixtures ---------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),   -- org member with real results
  ('22222222-2222-2222-2222-222222222222', 'iris@test.local'),    -- instructor of alice's org
  ('33333333-3333-3333-3333-333333333333', 'ollie@test.local'),   -- outsider instructor (different org)
  ('44444444-4444-4444-4444-444444444444', 'mia@test.local'),     -- plain member of alice's org (not instructor)
  ('55555555-5555-5555-5555-555555555555', 'nina@test.local');    -- invitee for invitation tests

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CREATE OR REPLACE PROCEDURE test_reset() LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', false);
END;
$$;

-- alice creates "acme-security" (auto team_owner); iris and mia are added as
-- instructor / member respectively by the (superuser, bypasses RLS) fixture
-- setup, exactly as an org_admin would via the app's real member-management
-- UI/RLS path elsewhere.
INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'acme-security', 'Acme Security', '11111111-1111-1111-1111-111111111111');
INSERT INTO public.organization_members (organization_id, user_id, role) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'instructor'),
  ('aaaaaaaa-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', 'member');

-- ollie is instructor of a completely unrelated org.
INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('bbbbbbbb-0000-0000-0000-000000000002', 'globex-corp', 'Globex Corp', '33333333-3333-3333-3333-333333333333');
UPDATE public.organization_members SET role = 'instructor'
  WHERE organization_id = 'bbbbbbbb-0000-0000-0000-000000000002' AND user_id = '33333333-3333-3333-3333-333333333333';

-- ---- Look up seeded content IDs (postgres superuser bypasses RLS) ---------
CREATE TEMP TABLE t_ids AS SELECT 1 AS x;
ALTER TABLE t_ids
  ADD COLUMN quiz_id uuid, ADD COLUMN q1_id uuid, ADD COLUMN q1_correct uuid, ADD COLUMN q2_id uuid, ADD COLUMN q2_correct uuid,
  ADD COLUMN ctf_id uuid,
  ADD COLUMN investigation_id uuid,
  ADD COLUMN inv_mc1 uuid, ADD COLUMN inv_mc1_correct uuid,
  ADD COLUMN inv_text1 uuid, ADD COLUMN inv_text2 uuid,
  ADD COLUMN inv_mc2 uuid, ADD COLUMN inv_mc2_correct uuid,
  ADD COLUMN inv_mc3 uuid, ADD COLUMN inv_mc3_correct uuid,
  ADD COLUMN capstone_id uuid;

UPDATE t_ids SET quiz_id = (SELECT id FROM public.quizzes WHERE slug = 'sql-injection-comprehension-check');
UPDATE t_ids SET q1_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = t_ids.quiz_id AND order_index = 0);
UPDATE t_ids SET q1_correct = (SELECT id FROM public.quiz_choices WHERE question_id = t_ids.q1_id AND is_correct = true);
UPDATE t_ids SET q2_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = t_ids.quiz_id AND order_index = 1);
UPDATE t_ids SET q2_correct = (SELECT id FROM public.quiz_choices WHERE question_id = t_ids.q2_id AND is_correct = true);
UPDATE t_ids SET ctf_id = (SELECT id FROM public.ctf_challenges WHERE slug = 'web-sqli-login-bypass');
UPDATE t_ids SET investigation_id = (SELECT id FROM public.investigations WHERE slug = 'phishing-fake-invoice');

-- investigation_questions/investigation_choices are staff-only readable (the
-- hidden-answer-key pattern) -- these lookups MUST happen here, as the
-- postgres superuser, not later as alice.
UPDATE t_ids SET inv_mc1 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_ids.investigation_id AND question_text = 'What technique does this attack primarily rely on?');
UPDATE t_ids SET inv_mc1_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_ids.inv_mc1 AND is_correct = true);
UPDATE t_ids SET inv_text1 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_ids.investigation_id AND question_text = 'What is the domain used in the phishing link, exactly as it appears in the WHOIS record?');
UPDATE t_ids SET inv_text2 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_ids.investigation_id AND question_text = 'What source IP address actually used j.rivera''s VPN credentials to log in (per the login log)?');
UPDATE t_ids SET inv_mc2 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_ids.investigation_id AND question_text LIKE 'The WHOIS creation date is%');
UPDATE t_ids SET inv_mc2_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_ids.inv_mc2 AND is_correct = true);
UPDATE t_ids SET inv_mc3 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_ids.investigation_id AND question_text LIKE 'Based on the timeline, did the attacker%');
UPDATE t_ids SET inv_mc3_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_ids.inv_mc3 AND is_correct = true);

INSERT INTO public.capstones (id, slug, title, report_required, published)
VALUES ('cccccccc-0000-0000-0000-000000000003', 'test-capstone-org-visibility', 'Test Capstone', true, true);
UPDATE t_ids SET capstone_id = 'cccccccc-0000-0000-0000-000000000003';

GRANT SELECT ON t_ids TO authenticated;

DO $$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM t_ids
    WHERE quiz_id IS NULL OR q1_id IS NULL OR q1_correct IS NULL OR q2_id IS NULL OR q2_correct IS NULL
       OR ctf_id IS NULL OR investigation_id IS NULL OR capstone_id IS NULL
       OR inv_mc1 IS NULL OR inv_mc1_correct IS NULL OR inv_text1 IS NULL OR inv_text2 IS NULL
       OR inv_mc2 IS NULL OR inv_mc2_correct IS NULL OR inv_mc3 IS NULL OR inv_mc3_correct IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'FAIL: fixture lookups incomplete (% missing) -- did seeded content drift?', v_missing;
  END IF;
  RAISE NOTICE 'PASS: all fixture content resolved';
END $$;

-- ============================================================================
-- 1. Alice (a plain org member) produces real graded results via the real
--    RPCs/insert paths -- not planted fixture rows.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');

DO $$
DECLARE v_ids record; v_attempt public.quiz_attempts;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  SELECT * INTO v_attempt FROM public.submit_quiz_attempt(
    v_ids.quiz_id,
    jsonb_build_object(v_ids.q1_id::text, jsonb_build_array(v_ids.q1_correct), v_ids.q2_id::text, jsonb_build_array(v_ids.q2_correct))
  );
  IF v_attempt.passed IS NOT true THEN RAISE EXCEPTION 'FAIL: fixture quiz attempt should pass'; END IF;
END $$;

DO $$
DECLARE v_ids record; v_sub public.ctf_submissions;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  SELECT * INTO v_sub FROM public.submit_ctf_flag(v_ids.ctf_id, 'ICOREPEN{ung41ded_sql1_ftw}');
  IF v_sub.correct IS NOT true THEN RAISE EXCEPTION 'FAIL: fixture ctf submission should be correct'; END IF;
END $$;

DO $$
DECLARE v_ids record;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  INSERT INTO public.capstone_submissions (capstone_id, user_id, report_content, status)
  VALUES (v_ids.capstone_id, '11111111-1111-1111-1111-111111111111', 'Real report content for the fixture capstone.', 'submitted');
END $$;

DO $$
DECLARE v_ids record; v_submission public.investigation_submissions;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.investigation_id,
    jsonb_build_object(
      v_ids.inv_mc1::text, jsonb_build_array(v_ids.inv_mc1_correct),
      v_ids.inv_text1::text, 'invoice-billing-support.com',
      v_ids.inv_text2::text, '198.51.100.44',
      v_ids.inv_mc2::text, jsonb_build_array(v_ids.inv_mc2_correct),
      v_ids.inv_mc3::text, jsonb_build_array(v_ids.inv_mc3_correct)
    )
  );
  IF v_submission.passed IS NOT true THEN RAISE EXCEPTION 'FAIL: fixture investigation submission should pass'; END IF;
END $$;

DO $$
BEGIN
  RAISE NOTICE 'PASS: alice produced real quiz/ctf/capstone/investigation results via real grading paths';
END $$;

-- ============================================================================
-- 2. Iris (instructor of alice's org) can see all 4 of alice's real results.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_ids record; cnt int;
BEGIN
  SELECT * INTO v_ids FROM t_ids;

  SELECT count(*) INTO cnt FROM public.quiz_attempts WHERE user_id = '11111111-1111-1111-1111-111111111111' AND quiz_id = v_ids.quiz_id;
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: org instructor cannot see member quiz_attempts (%)', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.ctf_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111' AND challenge_id = v_ids.ctf_id;
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: org instructor cannot see member ctf_submissions (%)', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.capstone_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111' AND capstone_id = v_ids.capstone_id;
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: org instructor cannot see member capstone_submissions (%)', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.investigation_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111' AND investigation_id = v_ids.investigation_id;
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: org instructor cannot see member investigation_submissions (%)', cnt; END IF;

  RAISE NOTICE 'PASS: org instructor sees all 4 of a fellow member''s real graded results';
END $$;

-- ============================================================================
-- 3. Ollie (instructor of an unrelated org) sees NONE of it.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_ids record; cnt int;
BEGIN
  SELECT * INTO v_ids FROM t_ids;

  SELECT count(*) INTO cnt FROM public.quiz_attempts WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: outsider org instructor can see quiz_attempts (%)', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.ctf_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: outsider org instructor can see ctf_submissions (%)', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.capstone_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: outsider org instructor can see capstone_submissions (%)', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.investigation_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: outsider org instructor can see investigation_submissions (%)', cnt; END IF;

  RAISE NOTICE 'PASS: instructor of an unrelated org sees none of alice''s results';
END $$;

-- ============================================================================
-- 4. Mia (plain member of alice's org, NOT an instructor) also sees none.
-- ============================================================================
CALL test_act_as('44444444-4444-4444-4444-444444444444');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.quiz_attempts WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: a plain (non-instructor) org member can see another member''s quiz_attempts (%)', cnt; END IF;
  RAISE NOTICE 'PASS: a plain org member (not instructor/team_owner/org_admin) still cannot see a fellow member''s results';
END $$;

-- ============================================================================
-- 5. Invitations: happy path.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111'); -- alice: team_owner of acme-security
DO $$
DECLARE v_token text; v_member public.organization_members;
BEGIN
  SELECT public.create_organization_invitation('aaaaaaaa-0000-0000-0000-000000000001', 'nina@test.local', 'member') INTO v_token;
  IF v_token IS NULL OR length(v_token) < 32 THEN RAISE EXCEPTION 'FAIL: expected a real random token, got %', v_token; END IF;

  PERFORM set_config('icorepen_test.invite_token', v_token, false);
END $$;

CALL test_act_as('55555555-5555-5555-5555-555555555555'); -- nina accepts
DO $$
DECLARE v_token text; v_member public.organization_members;
BEGIN
  v_token := current_setting('icorepen_test.invite_token');
  SELECT * INTO v_member FROM public.accept_organization_invitation(v_token);
  IF v_member.organization_id <> 'aaaaaaaa-0000-0000-0000-000000000001' OR v_member.role <> 'member' THEN
    RAISE EXCEPTION 'FAIL: unexpected membership after accept: org=% role=%', v_member.organization_id, v_member.role;
  END IF;
  RAISE NOTICE 'PASS: invitation accepted, real membership row created';
END $$;

DO $$
DECLARE v_token text;
BEGIN
  v_token := current_setting('icorepen_test.invite_token');
  BEGIN
    PERFORM public.accept_organization_invitation(v_token);
    RAISE EXCEPTION 'FAIL: the same invitation token was accepted twice';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a token cannot be redeemed twice (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 6. Wrong-email rejection.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_token text;
BEGIN
  SELECT public.create_organization_invitation('aaaaaaaa-0000-0000-0000-000000000001', 'someone-else@test.local', 'member') INTO v_token;
  PERFORM set_config('icorepen_test.invite_token2', v_token, false);
END $$;

CALL test_act_as('55555555-5555-5555-5555-555555555555'); -- nina, whose email does not match
DO $$
DECLARE v_token text;
BEGIN
  v_token := current_setting('icorepen_test.invite_token2');
  BEGIN
    PERFORM public.accept_organization_invitation(v_token);
    RAISE EXCEPTION 'FAIL: accepted an invitation addressed to a different email';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an invitation cannot be accepted by an account with a different email (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 7. Expired and revoked invitations are rejected.
-- ============================================================================
CALL test_reset();
DO $$
DECLARE v_hash text;
BEGIN
  v_hash := encode(digest('expired-token-fixture', 'sha256'), 'hex');
  INSERT INTO public.organization_invitations (organization_id, email, role, invited_by, token_hash, expires_at)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'expired@test.local', 'member', '11111111-1111-1111-1111-111111111111', v_hash, now() - interval '1 day');

  v_hash := encode(digest('revoked-token-fixture', 'sha256'), 'hex');
  INSERT INTO public.organization_invitations (organization_id, email, role, invited_by, token_hash, revoked_at)
  VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'revoked@test.local', 'member', '11111111-1111-1111-1111-111111111111', v_hash, now());
END $$;

CALL test_act_as('44444444-4444-4444-4444-444444444444'); -- mia (arbitrary authenticated caller)
DO $$
BEGIN
  BEGIN
    PERFORM public.accept_organization_invitation('expired-token-fixture');
    RAISE EXCEPTION 'FAIL: accepted an expired invitation';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an expired invitation is rejected (%)', SQLSTATE;
  END;

  BEGIN
    PERFORM public.accept_organization_invitation('revoked-token-fixture');
    RAISE EXCEPTION 'FAIL: accepted a revoked invitation';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a revoked invitation is rejected (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 8. Seat limit is genuinely enforced, and only an org admin/team owner (not
--    a plain member) can create an invitation at all.
-- ============================================================================
CALL test_reset();
DO $$
BEGIN
  INSERT INTO public.organizations (id, slug, name, created_by, seat_limit)
  VALUES ('dddddddd-0000-0000-0000-000000000004', 'tiny-org', 'Tiny Org', '11111111-1111-1111-1111-111111111111', 1);
  -- seat_limit=1: alice (auto team_owner) already fills the only seat.
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  BEGIN
    PERFORM public.create_organization_invitation('dddddddd-0000-0000-0000-000000000004', 'overflow@test.local', 'member');
    RAISE EXCEPTION 'FAIL: invited past the organization''s seat_limit';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: seat_limit is genuinely enforced, not just stored (%)', SQLSTATE;
  END;
END $$;

CALL test_act_as('44444444-4444-4444-4444-444444444444'); -- mia: plain member of acme-security, not an admin
DO $$
BEGIN
  BEGIN
    PERFORM public.create_organization_invitation('aaaaaaaa-0000-0000-0000-000000000001', 'shouldnt-work@test.local', 'member');
    RAISE EXCEPTION 'FAIL: a plain member (not org admin/team owner) created an invitation';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: only an org admin/team owner can create an invitation (%)', SQLSTATE;
  END;
END $$;

CALL test_reset();
DROP PROCEDURE test_act_as(uuid);
DROP PROCEDURE test_reset();
DROP TABLE t_ids;

ROLLBACK;

\echo 'ALL ORG-INSTRUCTOR VISIBILITY AND INVITATION TESTS PASSED'
