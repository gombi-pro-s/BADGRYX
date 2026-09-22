-- ============================================================================
-- Proves the 3 more seeded investigations (20260922000011) are actually
-- completable end-to-end through the real grading RPC, same discipline as
-- 011_seeded_investigation_e2e.sql for the phishing case.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES ('11111111-1111-1111-1111-111111111111', 'alice@test.local');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ============================================================================
-- Helper-style pattern (repeated per investigation, as postgres superuser):
-- look up the investigation + every question + the correct choice for each
-- multiple_choice question, into a per-investigation TEMP TABLE, then
-- submit the real correct answers as alice and check pass/DEMONSTRATED.
-- ============================================================================

-- ---- Investigation 2: data-breach-timeline ---------------------------------
CREATE TEMP TABLE t_breach AS
SELECT (SELECT id FROM public.investigations WHERE slug = 'data-breach-timeline') AS investigation_id;
ALTER TABLE t_breach ADD COLUMN q1 uuid, ADD COLUMN q2 uuid, ADD COLUMN q2_correct uuid, ADD COLUMN q3 uuid, ADD COLUMN q4 uuid, ADD COLUMN q4_correct uuid;
UPDATE t_breach SET q1 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_breach.investigation_id AND order_index = 0);
UPDATE t_breach SET q2 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_breach.investigation_id AND order_index = 1);
UPDATE t_breach SET q2_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_breach.q2 AND is_correct = true);
UPDATE t_breach SET q3 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_breach.investigation_id AND order_index = 2);
UPDATE t_breach SET q4 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_breach.investigation_id AND order_index = 3);
UPDATE t_breach SET q4_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_breach.q4 AND is_correct = true);
GRANT SELECT ON t_breach TO authenticated;

-- ---- Investigation 3: social-engineering-pretext ---------------------------
CREATE TEMP TABLE t_social AS
SELECT (SELECT id FROM public.investigations WHERE slug = 'social-engineering-pretext') AS investigation_id;
ALTER TABLE t_social ADD COLUMN q1 uuid, ADD COLUMN q1_correct uuid, ADD COLUMN q2 uuid, ADD COLUMN q3 uuid, ADD COLUMN q3_correct uuid, ADD COLUMN q4 uuid;
UPDATE t_social SET q1 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_social.investigation_id AND order_index = 0);
UPDATE t_social SET q1_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_social.q1 AND is_correct = true);
UPDATE t_social SET q2 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_social.investigation_id AND order_index = 1);
UPDATE t_social SET q3 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_social.investigation_id AND order_index = 2);
UPDATE t_social SET q3_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_social.q3 AND is_correct = true);
UPDATE t_social SET q4 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_social.investigation_id AND order_index = 3);
GRANT SELECT ON t_social TO authenticated;

-- ---- Investigation 4: malware-beaconing-c2 ---------------------------------
CREATE TEMP TABLE t_c2 AS
SELECT (SELECT id FROM public.investigations WHERE slug = 'malware-beaconing-c2') AS investigation_id;
ALTER TABLE t_c2 ADD COLUMN q1 uuid, ADD COLUMN q2 uuid, ADD COLUMN q2_correct uuid, ADD COLUMN q3 uuid, ADD COLUMN q4 uuid, ADD COLUMN q4_correct uuid;
UPDATE t_c2 SET q1 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_c2.investigation_id AND order_index = 0);
UPDATE t_c2 SET q2 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_c2.investigation_id AND order_index = 1);
UPDATE t_c2 SET q2_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_c2.q2 AND is_correct = true);
UPDATE t_c2 SET q3 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_c2.investigation_id AND order_index = 2);
UPDATE t_c2 SET q4 = (SELECT id FROM public.investigation_questions WHERE investigation_id = t_c2.investigation_id AND order_index = 3);
UPDATE t_c2 SET q4_correct = (SELECT id FROM public.investigation_choices WHERE question_id = t_c2.q4 AND is_correct = true);
GRANT SELECT ON t_c2 TO authenticated;

DO $$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM t_breach WHERE investigation_id IS NULL OR q1 IS NULL OR q2 IS NULL OR q2_correct IS NULL OR q3 IS NULL OR q4 IS NULL OR q4_correct IS NULL;
  SELECT v_missing + count(*) INTO v_missing FROM t_social WHERE investigation_id IS NULL OR q1 IS NULL OR q1_correct IS NULL OR q2 IS NULL OR q3 IS NULL OR q3_correct IS NULL OR q4 IS NULL;
  SELECT v_missing + count(*) INTO v_missing FROM t_c2 WHERE investigation_id IS NULL OR q1 IS NULL OR q2 IS NULL OR q2_correct IS NULL OR q3 IS NULL OR q4 IS NULL OR q4_correct IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'FAIL: seeded investigation content is missing pieces across the 3 investigations (% NULL lookups)', v_missing;
  END IF;
  RAISE NOTICE 'PASS: all 3 seeded investigations exist with complete question/answer keys';
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- ============================================================================
-- 1. data-breach-timeline: correct answers pass with a perfect score.
-- ============================================================================
DO $$
DECLARE v_ids record; v_submission public.investigation_submissions;
BEGIN
  SELECT * INTO v_ids FROM t_breach;
  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.investigation_id,
    jsonb_build_object(
      v_ids.q1::text, '203.0.113.201',
      v_ids.q2::text, jsonb_build_array(v_ids.q2_correct),
      v_ids.q3::text, ' 4508382013 ',
      v_ids.q4::text, jsonb_build_array(v_ids.q4_correct)
    )
  );
  IF v_submission.passed IS NOT true OR v_submission.score <> 100 THEN
    RAISE EXCEPTION 'FAIL: data-breach-timeline expected a perfect passing score, got passed=% score=%', v_submission.passed, v_submission.score;
  END IF;
  RAISE NOTICE 'PASS: data-breach-timeline is genuinely solvable end-to-end';
END $$;

-- ============================================================================
-- 2. social-engineering-pretext: correct answers pass with a perfect score.
-- ============================================================================
DO $$
DECLARE v_ids record; v_submission public.investigation_submissions;
BEGIN
  SELECT * INTO v_ids FROM t_social;
  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.investigation_id,
    jsonb_build_object(
      v_ids.q1::text, jsonb_build_array(v_ids.q1_correct),
      v_ids.q2::text, 'DANA WHITFIELD',
      v_ids.q3::text, jsonb_build_array(v_ids.q3_correct),
      v_ids.q4::text, 'corp-example-support.com'
    )
  );
  IF v_submission.passed IS NOT true OR v_submission.score <> 100 THEN
    RAISE EXCEPTION 'FAIL: social-engineering-pretext expected a perfect passing score, got passed=% score=%', v_submission.passed, v_submission.score;
  END IF;
  RAISE NOTICE 'PASS: social-engineering-pretext is genuinely solvable end-to-end (including all-caps name normalization)';
END $$;

-- ============================================================================
-- 3. malware-beaconing-c2: correct answers pass with a perfect score.
-- ============================================================================
DO $$
DECLARE v_ids record; v_submission public.investigation_submissions;
BEGIN
  SELECT * INTO v_ids FROM t_c2;
  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.investigation_id,
    jsonb_build_object(
      v_ids.q1::text, '185.220.101.42',
      v_ids.q2::text, jsonb_build_array(v_ids.q2_correct),
      v_ids.q3::text, 'svchost_update.exe',
      v_ids.q4::text, jsonb_build_array(v_ids.q4_correct)
    )
  );
  IF v_submission.passed IS NOT true OR v_submission.score <> 100 THEN
    RAISE EXCEPTION 'FAIL: malware-beaconing-c2 expected a perfect passing score, got passed=% score=%', v_submission.passed, v_submission.score;
  END IF;
  RAISE NOTICE 'PASS: malware-beaconing-c2 is genuinely solvable end-to-end';
END $$;

-- ============================================================================
-- 4. A wrong answer on any one investigation genuinely fails (grading is
--    real, not a rubber stamp) -- spot-checked on malware-beaconing-c2.
-- ============================================================================
DO $$
DECLARE v_ids record; v_submission public.investigation_submissions;
BEGIN
  SELECT * INTO v_ids FROM t_c2;
  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.investigation_id,
    jsonb_build_object(v_ids.q1::text, '10.0.0.1', v_ids.q3::text, 'wrong.exe')
  );
  IF v_submission.passed IS NOT false THEN RAISE EXCEPTION 'FAIL: wrong answers should not pass'; END IF;
  IF v_submission.score <> 0 THEN RAISE EXCEPTION 'FAIL: expected score 0 for all-wrong answers, got %', v_submission.score; END IF;
  RAISE NOTICE 'PASS: wrong answers genuinely fail -- grading is real, not a rubber stamp';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);
DROP TABLE t_breach;
DROP TABLE t_social;
DROP TABLE t_c2;

ROLLBACK;

\echo 'ALL 3 MORE SEEDED INVESTIGATIONS END-TO-END TESTS PASSED'
