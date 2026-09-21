-- ============================================================================
-- Proves the seeded sample content (20260921000014) is not just present but
-- actually completable end-to-end through the real grading pipeline: read
-- the lesson, pass its quiz, complete its guided lab, solve its CTF
-- challenge, and watch the sql-injection skill state advance for real.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES ('11111111-1111-1111-1111-111111111111', 'alice@test.local');

-- ---- Look up seeded content IDs as postgres (superuser bypasses RLS) ------
-- This mirrors real usage: an authenticated learner reads quiz questions via
-- the quiz_questions_for_attempt view (which itself runs as the view owner,
-- bypassing RLS on the staff-only base tables) and CTF challenges via
-- ctf_challenges_public -- the actual GRADING calls below still run as
-- alice through her real RLS-respecting session, which is the real test.
CREATE TEMP TABLE test_ids AS
SELECT
  (SELECT id FROM public.skills WHERE slug = 'sql-injection') AS skill_id,
  (SELECT id FROM public.quizzes WHERE slug = 'sql-injection-comprehension-check') AS quiz_id,
  (SELECT id FROM public.labs WHERE slug = 'sqli-101') AS lab_id,
  (SELECT id FROM public.ctf_challenges_public WHERE slug = 'web-sqli-login-bypass') AS challenge_id;

ALTER TABLE test_ids ADD COLUMN q1_id uuid, ADD COLUMN q1_correct_choice uuid,
  ADD COLUMN q2_id uuid, ADD COLUMN q2_correct_choice uuid;

UPDATE test_ids SET
  q1_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = test_ids.quiz_id ORDER BY order_index LIMIT 1);
UPDATE test_ids SET
  q1_correct_choice = (SELECT id FROM public.quiz_choices WHERE question_id = test_ids.q1_id AND is_correct = true);
UPDATE test_ids SET
  q2_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = test_ids.quiz_id ORDER BY order_index OFFSET 1 LIMIT 1);
UPDATE test_ids SET
  q2_correct_choice = (SELECT id FROM public.quiz_choices WHERE question_id = test_ids.q2_id AND is_correct = true);

-- Scratch test-only table, dropped by the ROLLBACK at the end of this
-- script; granting SELECT to authenticated just lets the alice-context DO
-- blocks below read the IDs looked up above as postgres.
GRANT SELECT ON test_ids TO authenticated;

DO $$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM test_ids
    WHERE skill_id IS NULL OR quiz_id IS NULL OR lab_id IS NULL OR challenge_id IS NULL
       OR q1_id IS NULL OR q1_correct_choice IS NULL OR q2_id IS NULL OR q2_correct_choice IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'FAIL: seeded sample content (or its questions/choices) is missing';
  END IF;
  RAISE NOTICE 'PASS: seeded sample content exists (skill, quiz + questions, lab, CTF challenge)';
END $$;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- ---- Quiz: answer both questions correctly using the real answer key -----
DO $$
DECLARE
  v_ids record;
  v_attempt public.quiz_attempts;
  v_state public.skill_state;
BEGIN
  SELECT * INTO v_ids FROM test_ids;

  SELECT * INTO v_attempt FROM public.submit_quiz_attempt(
    v_ids.quiz_id,
    jsonb_build_object(
      v_ids.q1_id::text, jsonb_build_array(v_ids.q1_correct_choice),
      v_ids.q2_id::text, jsonb_build_array(v_ids.q2_correct_choice)
    )
  );
  IF NOT v_attempt.passed THEN
    RAISE EXCEPTION 'FAIL: seeded quiz not passed with the correct answers (score %)', v_attempt.score;
  END IF;
  RAISE NOTICE 'PASS: seeded quiz passed with its real answer key (score %)', v_attempt.score;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill_id;
  IF v_state <> 'PRACTICING' THEN
    RAISE EXCEPTION 'FAIL: expected PRACTICING after passing the seeded quiz, got %', v_state;
  END IF;
END $$;

-- ---- Guided lab: start an instance, submit the real flag ------------------
DO $$
DECLARE
  v_ids record;
  v_instance_id uuid;
  v_submission public.lab_submissions;
BEGIN
  SELECT * INTO v_ids FROM test_ids;

  INSERT INTO public.lab_instances (id, lab_id, user_id, guided, status)
  VALUES (gen_random_uuid(), v_ids.lab_id, '11111111-1111-1111-1111-111111111111', true, 'running')
  RETURNING id INTO v_instance_id;

  SELECT * INTO v_submission FROM public.submit_lab_flag(v_instance_id, 'ICOREPEN{sql1_4uth_byp4ss_101}');
  IF NOT v_submission.correct THEN
    RAISE EXCEPTION 'FAIL: the seeded lab''s documented flag was rejected';
  END IF;
  RAISE NOTICE 'PASS: seeded guided lab completed with its real flag';
END $$;

-- ---- CTF challenge: solve it (unguided -> DEMONSTRATED) -------------------
DO $$
DECLARE
  v_ids record;
  v_ctf_submission public.ctf_submissions;
  v_state public.skill_state;
BEGIN
  SELECT * INTO v_ids FROM test_ids;

  SELECT * INTO v_ctf_submission FROM public.submit_ctf_flag(v_ids.challenge_id, 'ICOREPEN{ung41ded_sql1_ftw}');
  IF NOT v_ctf_submission.correct OR v_ctf_submission.points_awarded <> 250 THEN
    RAISE EXCEPTION 'FAIL: the seeded CTF challenge''s documented flag was rejected or under-scored';
  END IF;
  RAISE NOTICE 'PASS: seeded CTF challenge solved with its real flag (250 points)';

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill_id;
  IF v_state <> 'DEMONSTRATED' THEN
    RAISE EXCEPTION 'FAIL: expected DEMONSTRATED after guided lab + CTF solve, got %', v_state;
  END IF;
  RAISE NOTICE 'PASS: sql-injection skill genuinely reached DEMONSTRATED via real seeded content';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL SEEDED CONTENT END-TO-END TESTS PASSED'
