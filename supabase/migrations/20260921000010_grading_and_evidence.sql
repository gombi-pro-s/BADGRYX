-- ============================================================================
-- Grading functions: the ONLY way skill_evidence, quiz_attempts,
-- lab_submissions, lab_progress, and ctf_submissions get written for a
-- normal user. Each function independently verifies the outcome against
-- server-held truth (correct-answer flags, hashed lab/CTF flags) before
-- recording anything -- a client can influence the *input* (answers, a
-- guessed flag) but never the *verdict*.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- submit_quiz_attempt: grades against quiz_choices.is_correct (a table the
-- caller cannot read), inserts quiz_attempts, and records 'theory' or
-- 'quiz' skill_evidence for every skill tied to the quiz depending on
-- whether it's a plain quiz or an exam.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_quiz_attempt(
  p_quiz_id uuid,
  p_answers jsonb -- {"<question_id>": ["<choice_id>", ...]}
)
  RETURNS public.quiz_attempts
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_quiz public.quizzes;
  v_total_points numeric := 0;
  v_earned_points numeric := 0;
  v_question record;
  v_selected uuid[];
  v_correct_ids uuid[];
  v_attempt public.quiz_attempts;
  v_prior_attempts int;
  v_skill_id uuid;
  v_outcome public.skill_evidence_outcome;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_quiz FROM public.quizzes WHERE id = p_quiz_id AND published = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'quiz not found or not published' USING ERRCODE = 'P0002';
  END IF;

  IF v_quiz.max_attempts IS NOT NULL THEN
    SELECT count(*) INTO v_prior_attempts FROM public.quiz_attempts
      WHERE quiz_id = p_quiz_id AND user_id = v_user_id;
    IF v_prior_attempts >= v_quiz.max_attempts THEN
      RAISE EXCEPTION 'maximum attempts reached' USING ERRCODE = 'P0003';
    END IF;
  END IF;

  FOR v_question IN
    SELECT id, points FROM public.quiz_questions WHERE quiz_id = p_quiz_id
  LOOP
    v_total_points := v_total_points + v_question.points;

    SELECT array_agg(id) INTO v_correct_ids
      FROM public.quiz_choices WHERE question_id = v_question.id AND is_correct = true;

    SELECT array(
      SELECT jsonb_array_elements_text(
        COALESCE(p_answers -> v_question.id::text, '[]'::jsonb)
      )::uuid
    ) INTO v_selected;

    IF v_selected IS NOT NULL AND v_correct_ids IS NOT NULL
       AND v_selected @> v_correct_ids AND v_correct_ids @> v_selected THEN
      v_earned_points := v_earned_points + v_question.points;
    END IF;
  END LOOP;

  INSERT INTO public.quiz_attempts (quiz_id, user_id, answers, score, passed)
  VALUES (
    p_quiz_id, v_user_id, p_answers,
    CASE WHEN v_total_points > 0 THEN round(v_earned_points / v_total_points * 100, 2) ELSE 0 END,
    (CASE WHEN v_total_points > 0 THEN (v_earned_points / v_total_points * 100) ELSE 0 END) >= v_quiz.passing_score
  )
  RETURNING * INTO v_attempt;

  v_outcome := CASE WHEN v_attempt.passed THEN 'passed' ELSE 'failed' END;

  FOR v_skill_id IN SELECT skill_id FROM public.quiz_skills WHERE quiz_id = p_quiz_id
  LOOP
    PERFORM public.record_skill_evidence(
      v_user_id, v_skill_id,
      (CASE WHEN v_quiz.is_exam THEN 'assessment' ELSE 'quiz' END)::public.skill_evidence_type,
      v_outcome, 'quiz', p_quiz_id, v_attempt.score, NULL,
      jsonb_build_object('quiz_attempt_id', v_attempt.id)
    );
  END LOOP;

  PERFORM public.log_audit_event('quiz.attempt.submitted', 'quiz', p_quiz_id::text, NULL,
    jsonb_build_object('passed', v_attempt.passed, 'score', v_attempt.score));

  RETURN v_attempt;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_quiz_attempt FROM public;
GRANT EXECUTE ON FUNCTION public.submit_quiz_attempt TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- submit_lab_flag: verifies digest(p_flag, 'sha256') against the stored
-- flag_hash for the instance's lab+variant. Records lab_submissions,
-- updates lab_progress, and on the FIRST correct submission for a given
-- instance, records skill_evidence (guided_lab or unguided_lab depending on
-- lab_instances.guided).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_lab_flag(
  p_lab_instance_id uuid,
  p_flag text
)
  RETURNS public.lab_submissions
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_instance public.lab_instances;
  v_flag public.lab_flags;
  v_submitted_hash text;
  v_correct boolean;
  v_submission public.lab_submissions;
  v_already_completed boolean;
  v_skill_id uuid;
  v_evidence_type public.skill_evidence_type;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_instance FROM public.lab_instances
    WHERE id = p_lab_instance_id AND user_id = v_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lab instance not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_instance.status NOT IN ('running', 'provisioning') THEN
    -- Note: P0004 is deliberately avoided -- it is Postgres' reserved
    -- SQLSTATE for assert_failure, which a plain `WHEN OTHERS` handler does
    -- NOT catch (along with query_canceled). P0005+ are undefined by
    -- Postgres and safe for application use.
    RAISE EXCEPTION 'lab instance is not active' USING ERRCODE = 'P0005';
  END IF;

  v_submitted_hash := encode(digest(p_flag, 'sha256'), 'hex');

  SELECT * INTO v_flag FROM public.lab_flags
    WHERE lab_id = v_instance.lab_id AND variant_seed = v_instance.variant_seed
      AND flag_hash = v_submitted_hash
    LIMIT 1;
  v_correct := FOUND;

  INSERT INTO public.lab_submissions (lab_instance_id, user_id, flag_id, correct)
  VALUES (p_lab_instance_id, v_user_id, v_flag.id, v_correct)
  RETURNING * INTO v_submission;

  SELECT EXISTS (
    SELECT 1 FROM public.lab_submissions
    WHERE lab_instance_id = p_lab_instance_id AND correct = true AND id <> v_submission.id
  ) INTO v_already_completed;

  INSERT INTO public.lab_progress (user_id, lab_id, status, attempts, last_attempt_at, first_completed_at)
  VALUES (
    v_user_id, v_instance.lab_id,
    (CASE WHEN v_correct THEN 'completed' ELSE 'in_progress' END)::public.lab_progress_status,
    1, now(), CASE WHEN v_correct THEN now() ELSE NULL END
  )
  ON CONFLICT (user_id, lab_id) DO UPDATE SET
    status = (CASE WHEN v_correct THEN 'completed' ELSE public.lab_progress.status::text END)::public.lab_progress_status,
    attempts = public.lab_progress.attempts + 1,
    last_attempt_at = now(),
    first_completed_at = COALESCE(public.lab_progress.first_completed_at, CASE WHEN v_correct THEN now() ELSE NULL END);

  IF v_correct AND NOT v_already_completed THEN
    v_evidence_type := CASE WHEN v_instance.guided THEN 'guided_lab' ELSE 'unguided_lab' END;
    FOR v_skill_id IN SELECT skill_id FROM public.lab_skills WHERE lab_id = v_instance.lab_id
    LOOP
      PERFORM public.record_skill_evidence(
        v_user_id, v_skill_id, v_evidence_type, 'passed', 'lab', v_instance.lab_id,
        NULL, NULL, jsonb_build_object('lab_instance_id', p_lab_instance_id)
      );
    END LOOP;

    UPDATE public.lab_instances SET status = 'stopped' WHERE id = p_lab_instance_id;
  END IF;

  PERFORM public.log_audit_event('lab.flag.submitted', 'lab_instance', p_lab_instance_id::text, NULL,
    jsonb_build_object('correct', v_correct));

  RETURN v_submission;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_lab_flag FROM public;
GRANT EXECUTE ON FUNCTION public.submit_lab_flag TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- submit_ctf_flag: same hashed-flag verification pattern. points_awarded is
-- only ever set on the FIRST correct submission (enforced additionally by
-- the partial unique index on ctf_submissions).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_ctf_flag(
  p_challenge_id uuid,
  p_flag text
)
  RETURNS public.ctf_submissions
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_challenge public.ctf_challenges;
  v_correct boolean;
  v_points integer := 0;
  v_already_solved boolean;
  v_submission public.ctf_submissions;
  v_skill_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_challenge FROM public.ctf_challenges WHERE id = p_challenge_id AND published = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'challenge not found or not published' USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.ctf_submissions WHERE challenge_id = p_challenge_id AND user_id = v_user_id AND correct = true
  ) INTO v_already_solved;

  v_correct := (encode(digest(p_flag, 'sha256'), 'hex') = v_challenge.flag_hash);

  IF v_correct AND v_already_solved THEN
    -- Already solved: a repeat-correct submission is not new information.
    -- Return the original scoring submission unchanged (idempotent) instead
    -- of inserting a second correct=true row, which the partial unique
    -- index ctf_submissions_one_correct_per_user would otherwise reject --
    -- that index is the hard defense-in-depth guarantee against
    -- double-scoring even if this function's own logic had a bug.
    SELECT * INTO v_submission FROM public.ctf_submissions
      WHERE challenge_id = p_challenge_id AND user_id = v_user_id AND correct = true
      LIMIT 1;
    RETURN v_submission;
  END IF;

  IF v_correct THEN
    v_points := v_challenge.points;
  END IF;

  INSERT INTO public.ctf_submissions (challenge_id, user_id, correct, points_awarded)
  VALUES (p_challenge_id, v_user_id, v_correct, v_points)
  RETURNING * INTO v_submission;

  IF v_correct THEN
    FOR v_skill_id IN SELECT skill_id FROM public.ctf_challenge_skills WHERE challenge_id = p_challenge_id
    LOOP
      PERFORM public.record_skill_evidence(
        v_user_id, v_skill_id, 'ctf', 'passed', 'ctf_challenge', p_challenge_id,
        v_points, NULL, jsonb_build_object('challenge_id', p_challenge_id)
      );
    END LOOP;
  END IF;

  PERFORM public.log_audit_event('ctf.flag.submitted', 'ctf_challenge', p_challenge_id::text, NULL,
    jsonb_build_object('correct', v_correct, 'points_awarded', v_points));

  RETURN v_submission;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_ctf_flag FROM public;
GRANT EXECUTE ON FUNCTION public.submit_ctf_flag TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- unlock_lab_hint: records a hint unlock for the caller's own lab instance.
-- A thin function rather than a raw insert so future point-cost deduction
-- logic has one enforcement point.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.unlock_lab_hint(p_lab_instance_id uuid, p_hint_id uuid)
  RETURNS public.lab_hint_unlocks
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_instance public.lab_instances;
  v_hint public.lab_hints;
  v_unlock public.lab_hint_unlocks;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_instance FROM public.lab_instances WHERE id = p_lab_instance_id AND user_id = v_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'lab instance not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_hint FROM public.lab_hints WHERE id = p_hint_id AND lab_id = v_instance.lab_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'hint not found for this lab' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.lab_hint_unlocks (lab_instance_id, hint_id)
  VALUES (p_lab_instance_id, p_hint_id)
  ON CONFLICT (lab_instance_id, hint_id) DO UPDATE SET unlocked_at = public.lab_hint_unlocks.unlocked_at
  RETURNING * INTO v_unlock;

  RETURN v_unlock;
END;
$$;

REVOKE ALL ON FUNCTION public.unlock_lab_hint FROM public;
GRANT EXECUTE ON FUNCTION public.unlock_lab_hint TO authenticated, service_role;
