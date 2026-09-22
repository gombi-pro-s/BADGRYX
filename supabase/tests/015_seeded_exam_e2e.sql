-- ============================================================================
-- Proves the seeded standalone exam quiz (20260922000014) is genuinely
-- reachable and solvable end-to-end through the real grading RPC: correct
-- answers pass, is_exam=true records 'assessment' (not 'quiz') skill
-- evidence, the sql-injection skill reaches ASSESSED, and a wrong multi-
-- select answer genuinely fails (no partial credit).
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

-- ---- Look up seeded content IDs (postgres superuser bypasses RLS) --------
CREATE TEMP TABLE t_ids AS SELECT 1 AS x;
ALTER TABLE t_ids
  ADD COLUMN quiz_id uuid, ADD COLUMN skill_id uuid,
  ADD COLUMN q1_id uuid, ADD COLUMN q1_correct uuid,
  ADD COLUMN q2_id uuid, ADD COLUMN q2_correct uuid,
  ADD COLUMN q3_id uuid, ADD COLUMN q3_correct uuid[],
  ADD COLUMN q3_wrong_choice uuid,
  ADD COLUMN q4_id uuid, ADD COLUMN q4_correct uuid;

UPDATE t_ids SET quiz_id = (SELECT id FROM public.quizzes WHERE slug = 'sql-injection-practical-assessment');
UPDATE t_ids SET skill_id = (SELECT id FROM public.skills WHERE slug = 'sql-injection');
UPDATE t_ids SET q1_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = t_ids.quiz_id AND order_index = 0);
UPDATE t_ids SET q1_correct = (SELECT id FROM public.quiz_choices WHERE question_id = t_ids.q1_id AND is_correct = true);
UPDATE t_ids SET q2_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = t_ids.quiz_id AND order_index = 1);
UPDATE t_ids SET q2_correct = (SELECT id FROM public.quiz_choices WHERE question_id = t_ids.q2_id AND is_correct = true);
UPDATE t_ids SET q3_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = t_ids.quiz_id AND order_index = 2);
UPDATE t_ids SET q3_correct = (SELECT array_agg(id) FROM public.quiz_choices WHERE question_id = t_ids.q3_id AND is_correct = true);
UPDATE t_ids SET q3_wrong_choice = (SELECT id FROM public.quiz_choices WHERE question_id = t_ids.q3_id AND is_correct = false LIMIT 1);
UPDATE t_ids SET q4_id = (SELECT id FROM public.quiz_questions WHERE quiz_id = t_ids.quiz_id AND order_index = 3);
UPDATE t_ids SET q4_correct = (SELECT id FROM public.quiz_choices WHERE question_id = t_ids.q4_id AND is_correct = true);

GRANT SELECT ON t_ids TO authenticated;

DO $$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM t_ids
    WHERE quiz_id IS NULL OR skill_id IS NULL
       OR q1_id IS NULL OR q1_correct IS NULL OR q2_id IS NULL OR q2_correct IS NULL
       OR q3_id IS NULL OR q3_correct IS NULL OR array_length(q3_correct, 1) <> 3 OR q3_wrong_choice IS NULL
       OR q4_id IS NULL OR q4_correct IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'FAIL: seeded exam quiz is missing pieces (% NULL/wrong lookups)', v_missing;
  END IF;
  RAISE NOTICE 'PASS: seeded exam quiz exists (4 questions, real answer key, is_exam=true)';
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- ============================================================================
-- 1. Correct answers pass, record 'assessment' (not 'quiz') evidence
--    because is_exam=true, and the skill reaches ASSESSED.
-- ============================================================================
DO $$
DECLARE
  v_ids record;
  v_attempt public.quiz_attempts;
  v_evidence_type public.skill_evidence_type;
  v_state public.skill_state;
BEGIN
  SELECT * INTO v_ids FROM t_ids;

  SELECT * INTO v_attempt FROM public.submit_quiz_attempt(
    v_ids.quiz_id,
    jsonb_build_object(
      v_ids.q1_id::text, jsonb_build_array(v_ids.q1_correct),
      v_ids.q2_id::text, jsonb_build_array(v_ids.q2_correct),
      v_ids.q3_id::text, to_jsonb(v_ids.q3_correct),
      v_ids.q4_id::text, jsonb_build_array(v_ids.q4_correct)
    )
  );

  IF v_attempt.passed IS NOT true OR v_attempt.score <> 100 THEN
    RAISE EXCEPTION 'FAIL: the seeded exam should pass with a perfect score, got passed=% score=%', v_attempt.passed, v_attempt.score;
  END IF;

  SELECT evidence_type INTO v_evidence_type FROM public.skill_evidence
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill_id
    ORDER BY occurred_at DESC, seq DESC LIMIT 1;
  IF v_evidence_type <> 'assessment' THEN
    RAISE EXCEPTION 'FAIL: is_exam=true should record ''assessment'' evidence, got %', v_evidence_type;
  END IF;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.skill_id;
  IF v_state <> 'ASSESSED' THEN
    RAISE EXCEPTION 'FAIL: expected ASSESSED after a passed exam with no prior demonstration, got %', v_state;
  END IF;

  RAISE NOTICE 'PASS: the seeded exam is genuinely solvable end-to-end -- perfect score, real ''assessment'' evidence, skill reaches ASSESSED';
END $$;

-- ============================================================================
-- 2. A wrong multi-select answer (missing one correct choice) genuinely
--    fails that question -- no partial credit, exact-set grading is real.
-- ============================================================================
DO $$
DECLARE v_ids record; v_attempt public.quiz_attempts; v_incomplete_q3 uuid[];
BEGIN
  SELECT * INTO v_ids FROM t_ids;
  v_incomplete_q3 := v_ids.q3_correct[1:2]; -- only 2 of the 3 correct choices

  SELECT * INTO v_attempt FROM public.submit_quiz_attempt(
    v_ids.quiz_id,
    jsonb_build_object(
      v_ids.q1_id::text, jsonb_build_array(v_ids.q1_correct),
      v_ids.q2_id::text, jsonb_build_array(v_ids.q2_correct),
      v_ids.q3_id::text, to_jsonb(v_incomplete_q3),
      v_ids.q4_id::text, jsonb_build_array(v_ids.q4_correct)
    )
  );

  -- 3 of 5 points (q3 worth 2 is entirely missed) = 60%, below the 80% passing score.
  IF v_attempt.passed IS NOT false THEN RAISE EXCEPTION 'FAIL: an incomplete multi-select answer should not earn credit for that question'; END IF;
  IF v_attempt.score <> 60 THEN RAISE EXCEPTION 'FAIL: expected score 60 (3/5 points), got %', v_attempt.score; END IF;
  RAISE NOTICE 'PASS: multi_choice grading is exact-set, not partial credit -- a genuinely incomplete answer fails';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);
DROP TABLE t_ids;

ROLLBACK;

\echo 'ALL SEEDED EXAM END-TO-END TESTS PASSED'
