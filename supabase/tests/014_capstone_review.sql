-- ============================================================================
-- Proves the capstone review lifecycle (20260922000013) is real, not just
-- schema-valid: a learner can submit a report directly (existing RLS path),
-- direct client UPDATEs to capstone_submissions are rejected outright (the
-- policy was dropped), only review_capstone_submission() can change status,
-- staff cannot review their own submission, a passed review genuinely
-- advances the linked skill to DEMONSTRATED via real skill_evidence
-- (capstone_skills was defined since day one but never actually used until
-- this migration), and a needs_revision review records a real failed
-- attempt rather than silently dropping it.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local');
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '33333333-3333-3333-3333-333333333333';
INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-3333-3333-333333333333', 'admin')
  ON CONFLICT DO NOTHING;

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

-- ---- Fixture capstones, each tagged to a distinct real seeded skill -------
CREATE TEMP TABLE t_ids AS SELECT 1 AS x;
ALTER TABLE t_ids ADD COLUMN capstone1_id uuid, ADD COLUMN capstone2_id uuid, ADD COLUMN skill1_id uuid, ADD COLUMN skill2_id uuid;

UPDATE t_ids SET skill1_id = (SELECT id FROM public.skills WHERE slug = 'sql-injection');
UPDATE t_ids SET skill2_id = (SELECT id FROM public.skills WHERE slug = 'digital-forensics');

INSERT INTO public.capstones (id, slug, title, description, report_required, published)
VALUES ('cccccccc-0000-0000-0000-000000000001', 'capstone-review-test-1', 'Capstone Review Test 1', 'Fixture', true, true);
INSERT INTO public.capstones (id, slug, title, description, report_required, published)
VALUES ('cccccccc-0000-0000-0000-000000000002', 'capstone-review-test-2', 'Capstone Review Test 2', 'Fixture', true, true);
UPDATE t_ids SET capstone1_id = 'cccccccc-0000-0000-0000-000000000001', capstone2_id = 'cccccccc-0000-0000-0000-000000000002';

INSERT INTO public.capstone_skills (capstone_id, skill_id)
  SELECT capstone1_id, skill1_id FROM t_ids;
INSERT INTO public.capstone_skills (capstone_id, skill_id)
  SELECT capstone2_id, skill2_id FROM t_ids;

GRANT SELECT ON t_ids TO authenticated;

DO $$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM t_ids WHERE capstone1_id IS NULL OR capstone2_id IS NULL OR skill1_id IS NULL OR skill2_id IS NULL;
  IF v_missing > 0 THEN RAISE EXCEPTION 'FAIL: fixture setup incomplete (% missing)', v_missing; END IF;
  RAISE NOTICE 'PASS: fixture capstones and skill links exist';
END $$;

-- ============================================================================
-- 1. Alice can submit a capstone report directly (existing INSERT RLS path).
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_ids record; v_submission_id uuid;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  INSERT INTO public.capstone_submissions (capstone_id, user_id, report_content)
  VALUES (v_ids.capstone1_id, '11111111-1111-1111-1111-111111111111', 'A real report describing the SQL injection capstone work.')
  RETURNING id INTO v_submission_id;
  PERFORM set_config('icorepen_test.submission1_id', v_submission_id::text, false);
  RAISE NOTICE 'PASS: alice submitted a capstone report';
END $$;

-- ============================================================================
-- 2. A direct client UPDATE to capstone_submissions is rejected outright --
--    the policy was dropped; review_capstone_submission() is the only path.
-- ============================================================================
DO $$
DECLARE v_id uuid; affected int;
BEGIN
  v_id := current_setting('icorepen_test.submission1_id')::uuid;
  UPDATE public.capstone_submissions SET status = 'passed' WHERE id = v_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'FAIL: a direct client UPDATE changed capstone_submissions.status (% rows)', affected; END IF;
  RAISE NOTICE 'PASS: a direct client UPDATE to capstone_submissions silently affects zero rows (no UPDATE policy exists)';
END $$;

-- ============================================================================
-- 3. Bob (not staff) cannot call review_capstone_submission() at all.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := current_setting('icorepen_test.submission1_id')::uuid;
  BEGIN
    PERFORM public.review_capstone_submission(v_id, 'passed', 'looks good');
    RAISE EXCEPTION 'FAIL: a non-staff user reviewed a capstone submission';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: only staff can call review_capstone_submission() (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 4. Staff cannot review their OWN submission.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_ids record; v_own_submission_id uuid;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  INSERT INTO public.capstone_submissions (capstone_id, user_id, report_content)
  VALUES (v_ids.capstone2_id, '33333333-3333-3333-3333-333333333333', 'Admin''s own capstone report.')
  RETURNING id INTO v_own_submission_id;

  BEGIN
    PERFORM public.review_capstone_submission(v_own_submission_id, 'passed', 'self-approved');
    RAISE EXCEPTION 'FAIL: staff reviewed their own capstone submission';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: staff cannot review their own submission (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 5. Staff reviewing alice's submission as 'passed' genuinely advances the
--    linked skill to DEMONSTRATED via real skill_evidence -- capstone_skills
--    actually gets used for the first time.
-- ============================================================================
DO $$
DECLARE
  v_ids record;
  v_submission_id uuid;
  v_result public.capstone_submissions;
  v_state public.skill_state;
  v_evidence_count int;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  v_submission_id := current_setting('icorepen_test.submission1_id')::uuid;

  SELECT * INTO v_result FROM public.review_capstone_submission(v_submission_id, 'passed', 'Excellent work, approved.');
  IF v_result.status <> 'passed' OR v_result.reviewer_id <> '33333333-3333-3333-3333-333333333333' THEN
    RAISE EXCEPTION 'FAIL: unexpected review result: status=% reviewer=%', v_result.status, v_result.reviewer_id;
  END IF;

  SELECT count(*) INTO v_evidence_count FROM public.skill_evidence
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill1_id
      AND evidence_type = 'capstone' AND outcome = 'passed';
  IF v_evidence_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected exactly 1 passed capstone evidence row, got %', v_evidence_count; END IF;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill1_id;
  IF v_state <> 'DEMONSTRATED' THEN RAISE EXCEPTION 'FAIL: expected DEMONSTRATED after a passed capstone, got %', v_state; END IF;

  RAISE NOTICE 'PASS: a passed capstone review records real skill_evidence and genuinely advances the linked skill to DEMONSTRATED';
END $$;

-- ============================================================================
-- 6. An already-passed submission cannot be re-reviewed.
-- ============================================================================
DO $$
DECLARE v_id uuid;
BEGIN
  v_id := current_setting('icorepen_test.submission1_id')::uuid;
  BEGIN
    PERFORM public.review_capstone_submission(v_id, 'needs_revision', 'changed my mind');
    RAISE EXCEPTION 'FAIL: an already-passed submission was re-reviewed';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: an already-passed submission cannot be re-reviewed (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 7. A 'needs_revision' review records a genuine FAILED evidence row (not
--    silently dropped), and does not advance the skill.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_ids record; v_submission_id uuid;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  INSERT INTO public.capstone_submissions (capstone_id, user_id, report_content)
  VALUES (v_ids.capstone2_id, '11111111-1111-1111-1111-111111111111', 'A weaker report on the forensics capstone.')
  RETURNING id INTO v_submission_id;
  PERFORM set_config('icorepen_test.submission2_id', v_submission_id::text, false);
END $$;

CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE
  v_ids record;
  v_submission_id uuid;
  v_evidence_count int;
  v_state public.skill_state;
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  v_submission_id := current_setting('icorepen_test.submission2_id')::uuid;

  PERFORM public.review_capstone_submission(v_submission_id, 'needs_revision', 'Missing remediation steps -- please expand.');

  SELECT count(*) INTO v_evidence_count FROM public.skill_evidence
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill2_id
      AND evidence_type = 'capstone' AND outcome = 'failed';
  IF v_evidence_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected exactly 1 failed capstone evidence row, got %', v_evidence_count; END IF;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill2_id;
  IF v_state IS DISTINCT FROM 'NOT_STARTED' THEN
    RAISE EXCEPTION 'FAIL: a needs_revision-only capstone should not advance the skill, got %', v_state;
  END IF;

  RAISE NOTICE 'PASS: a needs_revision review records a real failed evidence row and does not advance the skill';
END $$;

CALL test_reset();
DROP PROCEDURE test_act_as(uuid);
DROP PROCEDURE test_reset();
DROP TABLE t_ids;

ROLLBACK;

\echo 'ALL CAPSTONE REVIEW TESTS PASSED'
