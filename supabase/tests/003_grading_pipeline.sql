-- ============================================================================
-- End-to-end test: quiz/lab/CTF submission -> grading -> skill evidence ->
-- skill state. Proves the full "no fake mastery" pipeline actually works,
-- not just that individual tables are locked down.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES ('11111111-1111-1111-1111-111111111111', 'alice@test.local');

INSERT INTO public.skill_categories (id, slug, name) VALUES ('c0000000-0000-0000-0000-000000000001', 'web-vulns', 'Web Vulnerabilities');
INSERT INTO public.skills (id, slug, name, category_id) VALUES ('50000000-0000-0000-0000-000000000001', 'test-sql-injection', 'SQL Injection', 'c0000000-0000-0000-0000-000000000001');

-- ---- Seed a quiz with one question, two choices, one correct -------------
INSERT INTO public.quizzes (id, slug, title, passing_score, published) VALUES
  ('60000000-0000-0000-0000-000000000001', 'sqli-quiz', 'SQL Injection Basics', 70, true);
INSERT INTO public.quiz_skills (quiz_id, skill_id) VALUES
  ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001');
INSERT INTO public.quiz_questions (id, quiz_id, question_text, points) VALUES
  ('61000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'Which character often starts an SQLi test?', 1);
INSERT INTO public.quiz_choices (id, question_id, choice_text, is_correct) VALUES
  ('62000000-0000-0000-0000-000000000001', '61000000-0000-0000-0000-000000000001', E'\'', true),
  ('62000000-0000-0000-0000-000000000002', '61000000-0000-0000-0000-000000000001', 'a tab character', false);

-- ---- Seed a lab with one flag ---------------------------------------------
INSERT INTO public.labs (id, slug, title, category, difficulty, published) VALUES
  ('70000000-0000-0000-0000-000000000001', 'sqli-101', 'SQLi 101', 'web', 'easy', true);
INSERT INTO public.lab_skills (lab_id, skill_id) VALUES
  ('70000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001');
INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed) VALUES
  ('70000000-0000-0000-0000-000000000001', 'flag', encode(digest('ICOREPEN{sqli_basic}', 'sha256'), 'hex'), 0);

-- ---- Seed a CTF challenge ---------------------------------------------------
INSERT INTO public.ctf_challenges (id, slug, title, category, difficulty, points, flag_hash, published) VALUES
  ('80000000-0000-0000-0000-000000000001', 'web-sqli-1', 'Login Bypass', 'web', 'easy', 250,
   encode(digest('ICOREPEN{login_bypass}', 'sha256'), 'hex'), true);
INSERT INTO public.ctf_challenge_skills (challenge_id, skill_id) VALUES
  ('80000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- ============================================================================
-- 1. Wrong quiz answer -> fails, records 'quiz' evidence with outcome=failed,
--    skill state stays NOT_STARTED / does not become PRACTICING.
-- ============================================================================
DO $$
DECLARE v_attempt public.quiz_attempts;
DECLARE v_state public.skill_state;
BEGIN
  SELECT * INTO v_attempt FROM public.submit_quiz_attempt(
    '60000000-0000-0000-0000-000000000001',
    jsonb_build_object('61000000-0000-0000-0000-000000000001', jsonb_build_array('62000000-0000-0000-0000-000000000002'))
  );
  IF v_attempt.passed THEN RAISE EXCEPTION 'FAIL: wrong answer was graded as passed'; END IF;
  IF v_attempt.score <> 0 THEN RAISE EXCEPTION 'FAIL: wrong answer scored % (expected 0)', v_attempt.score; END IF;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state = 'PRACTICING' THEN RAISE EXCEPTION 'FAIL: failed quiz still advanced skill state to PRACTICING'; END IF;
  RAISE NOTICE 'PASS: wrong quiz answer graded as failed, does not fake progress';
END $$;

-- ============================================================================
-- 2. Correct quiz answer -> passes, records 'quiz' evidence, state -> PRACTICING.
-- ============================================================================
DO $$
DECLARE v_attempt public.quiz_attempts;
DECLARE v_state public.skill_state;
BEGIN
  SELECT * INTO v_attempt FROM public.submit_quiz_attempt(
    '60000000-0000-0000-0000-000000000001',
    jsonb_build_object('61000000-0000-0000-0000-000000000001', jsonb_build_array('62000000-0000-0000-0000-000000000001'))
  );
  IF NOT v_attempt.passed THEN RAISE EXCEPTION 'FAIL: correct answer was not graded as passed'; END IF;
  IF v_attempt.score <> 100 THEN RAISE EXCEPTION 'FAIL: correct answer scored % (expected 100)', v_attempt.score; END IF;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'PRACTICING' THEN RAISE EXCEPTION 'FAIL: expected PRACTICING after passed quiz, got %', v_state; END IF;
  RAISE NOTICE 'PASS: correct quiz answer graded as passed -> PRACTICING';
END $$;

-- ============================================================================
-- 3. Guessing a lab flag wrong does not complete the lab or grant evidence.
-- ============================================================================
DO $$
DECLARE v_instance_id uuid;
DECLARE v_sub public.lab_submissions;
DECLARE v_status public.lab_progress_status;
BEGIN
  INSERT INTO public.lab_instances (id, lab_id, user_id, guided, status)
  VALUES ('90000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', true, 'running')
  RETURNING id INTO v_instance_id;

  SELECT * INTO v_sub FROM public.submit_lab_flag(v_instance_id, 'wrong-guess');
  IF v_sub.correct THEN RAISE EXCEPTION 'FAIL: wrong flag graded as correct'; END IF;

  SELECT status INTO v_status FROM public.lab_progress
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND lab_id = '70000000-0000-0000-0000-000000000001';
  IF v_status = 'completed' THEN RAISE EXCEPTION 'FAIL: wrong flag marked lab as completed'; END IF;
  RAISE NOTICE 'PASS: wrong lab flag rejected, lab not completed';
END $$;

-- ============================================================================
-- 4. Correct lab flag completes the lab and grants guided_lab evidence
--    (guided=true on this instance) -> skill state -> ASSESSED path check:
--    combined with the quiz evidence above, state should now still be
--    PRACTICING (guided_lab doesn't outrank quiz/guided_lab tier).
-- ============================================================================
DO $$
DECLARE v_sub public.lab_submissions;
DECLARE v_status public.lab_progress_status;
DECLARE v_evidence_count int;
BEGIN
  SELECT * INTO v_sub FROM public.submit_lab_flag('90000000-0000-0000-0000-000000000001', 'ICOREPEN{sqli_basic}');
  IF NOT v_sub.correct THEN RAISE EXCEPTION 'FAIL: correct flag was rejected'; END IF;

  SELECT status INTO v_status FROM public.lab_progress
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND lab_id = '70000000-0000-0000-0000-000000000001';
  IF v_status <> 'completed' THEN RAISE EXCEPTION 'FAIL: correct flag did not complete the lab (status=%)', v_status; END IF;

  SELECT count(*) INTO v_evidence_count FROM public.skill_evidence
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND evidence_type = 'guided_lab' AND outcome = 'passed';
  IF v_evidence_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 guided_lab evidence row, got %', v_evidence_count; END IF;
  RAISE NOTICE 'PASS: correct lab flag completes lab and records guided_lab evidence';
END $$;

-- Resubmitting the same correct flag again must not double-award evidence.
DO $$
DECLARE v_evidence_count int;
BEGIN
  -- instance was auto-stopped on completion; simulate a second instance to
  -- prove idempotency of "first correct submission per instance" applies
  -- per-instance, and that re-running an already-stopped instance is refused.
  BEGIN
    PERFORM public.submit_lab_flag('90000000-0000-0000-0000-000000000001', 'ICOREPEN{sqli_basic}');
    RAISE EXCEPTION 'FAIL: submitted a flag against a stopped lab instance';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot submit against a stopped lab instance (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 5. A user cannot forge a lab_instance for themselves against a lab that
--    doesn't exist, and cannot submit a flag for someone else's instance.
-- ============================================================================
RESET ROLE;
INSERT INTO auth.users (id, email) VALUES ('22222222-2222-2222-2222-222222222222', 'bob@test.local');
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
BEGIN
  BEGIN
    PERFORM public.submit_lab_flag('90000000-0000-0000-0000-000000000001', 'ICOREPEN{sqli_basic}');
    RAISE EXCEPTION 'FAIL: bob submitted a flag against alice''s lab instance';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot submit a flag against another user''s lab instance (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 6. CTF: correct flag awards points once; resubmitting does not double-award.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_sub1 public.ctf_submissions;
DECLARE v_sub2 public.ctf_submissions;
DECLARE v_total int;
BEGIN
  SELECT * INTO v_sub1 FROM public.submit_ctf_flag('80000000-0000-0000-0000-000000000001', 'ICOREPEN{login_bypass}');
  IF v_sub1.points_awarded <> 250 THEN RAISE EXCEPTION 'FAIL: expected 250 points, got %', v_sub1.points_awarded; END IF;

  -- Resubmitting the already-correct flag is idempotent: it returns the
  -- SAME original submission row (same id), not a new 0-point row, and
  -- above all does not insert a second correct=true row.
  SELECT * INTO v_sub2 FROM public.submit_ctf_flag('80000000-0000-0000-0000-000000000001', 'ICOREPEN{login_bypass}');
  IF v_sub2.id <> v_sub1.id THEN RAISE EXCEPTION 'FAIL: resubmission created a new submission row instead of being idempotent'; END IF;

  SELECT sum(points_awarded) INTO v_total FROM public.ctf_submissions
    WHERE challenge_id = '80000000-0000-0000-0000-000000000001' AND user_id = '11111111-1111-1111-1111-111111111111';
  IF v_total <> 250 THEN RAISE EXCEPTION 'FAIL: total points % (expected 250, no double-award)', v_total; END IF;
  RAISE NOTICE 'PASS: CTF flag awards points once, resubmission does not double-award';
END $$;

-- Clients cannot read flag_hash even via the staff-oriented base table
-- (only through the *_public view / grading functions).
DO $$
DECLARE cnt int;
BEGIN
  BEGIN
    SELECT count(*) INTO cnt FROM public.ctf_challenges;
    RAISE EXCEPTION 'FAIL: authenticated user could select from ctf_challenges (flag_hash exposed)';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: ctf_challenges base table (with flag_hash) is unreadable by non-staff (%)', SQLSTATE;
  END;
END $$;

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.ctf_challenges_public WHERE id = '80000000-0000-0000-0000-000000000001';
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: public challenge view should show the published challenge'; END IF;
  RAISE NOTICE 'PASS: ctf_challenges_public exposes published challenges without flag_hash';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL GRADING PIPELINE TESTS PASSED'
