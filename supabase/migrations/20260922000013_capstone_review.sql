-- ============================================================================
-- Capstone submission/review: capstones/capstone_submissions have existed
-- since 20260921000008_content_model.sql (a learner can already INSERT a
-- report directly, per capstone_submissions_insert_own), but nothing has
-- ever reviewed one -- capstone_submissions_update_staff let any staff
-- member UPDATE any column with no state-transition validation, no audit
-- trail, and (a real gap) never fed capstone_skills into the skill graph at
-- all, leaving that link column entirely unused. This migration closes both
-- gaps, mirroring the scanner finding status lifecycle (ADR 0008): a single
-- SECURITY DEFINER function is the only way a submission's status changes.
-- ============================================================================

-- 'capstone' evidence is independent demonstration -- a staff-reviewed,
-- passed capstone project is at least as strong a signal of independent
-- practical ability as an unguided lab or CTF solve. See
-- recompute_skill_state() below, re-declared to treat it identically to
-- unguided_lab/ctf/investigation for DEMONSTRATED/MASTERED.
ALTER TYPE public.skill_evidence_type ADD VALUE 'capstone';

-- ----------------------------------------------------------------------------
-- recompute_skill_state(): re-declared with 'capstone' added everywhere
-- 'unguided_lab'/'ctf'/'investigation' already appear. Everything else is
-- identical to 20260922000009_investigations.sql's version.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.recompute_skill_state(p_user_id uuid, p_skill_id uuid)
  RETURNS public.skill_state
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_has_theory boolean;
  v_has_quiz boolean;
  v_has_guided_lab boolean;
  v_has_unguided_lab boolean;
  v_has_ctf boolean;
  v_has_investigation boolean;
  v_has_capstone boolean;
  v_has_assessment boolean;
  v_has_retest boolean;
  v_latest_gate_outcome public.skill_evidence_outcome;
  v_ever_assessed boolean;
  v_state public.skill_state;
BEGIN
  SELECT
    bool_or(evidence_type = 'theory' AND outcome = 'passed'),
    bool_or(evidence_type = 'quiz' AND outcome = 'passed'),
    bool_or(evidence_type = 'guided_lab' AND outcome = 'passed'),
    bool_or(evidence_type = 'unguided_lab' AND outcome = 'passed'),
    bool_or(evidence_type = 'ctf' AND outcome = 'passed'),
    bool_or(evidence_type = 'investigation' AND outcome = 'passed'),
    bool_or(evidence_type = 'capstone' AND outcome = 'passed'),
    bool_or(evidence_type = 'assessment' AND outcome = 'passed'),
    bool_or(evidence_type = 'retest' AND outcome = 'passed')
  INTO v_has_theory, v_has_quiz, v_has_guided_lab, v_has_unguided_lab,
       v_has_ctf, v_has_investigation, v_has_capstone, v_has_assessment, v_has_retest
  FROM public.skill_evidence
  WHERE user_id = p_user_id AND skill_id = p_skill_id;

  SELECT outcome INTO v_latest_gate_outcome
  FROM public.skill_evidence
  WHERE user_id = p_user_id AND skill_id = p_skill_id
    AND evidence_type IN ('assessment', 'retest')
  ORDER BY occurred_at DESC, seq DESC
  LIMIT 1;

  SELECT EXISTS (
    SELECT 1 FROM public.user_skill_states
    WHERE user_id = p_user_id AND skill_id = p_skill_id
      AND state IN ('ASSESSED', 'DEMONSTRATED', 'MASTERED')
  ) INTO v_ever_assessed;

  IF v_latest_gate_outcome = 'failed' AND v_ever_assessed THEN
    v_state := 'NEEDS_REVIEW';
  ELSIF v_has_assessment AND (v_has_unguided_lab OR v_has_ctf OR v_has_investigation OR v_has_capstone) AND v_has_retest THEN
    v_state := 'MASTERED';
  ELSIF v_has_unguided_lab OR v_has_ctf OR v_has_investigation OR v_has_capstone THEN
    v_state := 'DEMONSTRATED';
  ELSIF v_has_assessment THEN
    v_state := 'ASSESSED';
  ELSIF v_has_guided_lab OR v_has_quiz THEN
    v_state := 'PRACTICING';
  ELSIF v_has_theory THEN
    v_state := 'LEARNING';
  ELSE
    v_state := 'NOT_STARTED';
  END IF;

  INSERT INTO public.user_skill_states (user_id, skill_id, state, updated_at)
  VALUES (p_user_id, p_skill_id, v_state, now())
  ON CONFLICT (user_id, skill_id) DO UPDATE SET state = v_state, updated_at = now();

  RETURN v_state;
END;
$$;

REVOKE ALL ON FUNCTION public.recompute_skill_state FROM public;

-- ----------------------------------------------------------------------------
-- review_capstone_submission(): the only way a submission's status/reviewer
-- fields change. Independently re-verifies staff status (RLS is bypassed
-- inside SECURITY DEFINER) and blocks a staff member from reviewing their
-- own submission. A 'passed' review records real 'capstone' skill_evidence
-- for every skill this capstone is tagged with (capstone_skills, unused
-- until now); a 'needs_revision' review records a genuine failed attempt,
-- not silently dropped -- the learner can resubmit (a new row; there is no
-- uniqueness constraint on capstone_submissions, same as lab/ctf
-- submissions allowing multiple attempts).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.review_capstone_submission(
  p_submission_id uuid,
  p_status public.capstone_status,
  p_notes text DEFAULT NULL
)
  RETURNS public.capstone_submissions
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_reviewer_id uuid := auth.uid();
  v_submission public.capstone_submissions;
  v_skill_id uuid;
  v_outcome public.skill_evidence_outcome;
BEGIN
  IF v_reviewer_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'only staff can review a capstone submission' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('under_review', 'passed', 'needs_revision') THEN
    RAISE EXCEPTION 'a review cannot set status back to submitted' USING ERRCODE = 'P0005';
  END IF;

  SELECT * INTO v_submission FROM public.capstone_submissions WHERE id = p_submission_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'submission not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_submission.user_id = v_reviewer_id THEN
    RAISE EXCEPTION 'cannot review your own submission' USING ERRCODE = '42501';
  END IF;
  IF v_submission.status = 'passed' THEN
    RAISE EXCEPTION 'this submission has already been passed and cannot be re-reviewed' USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.capstone_submissions
  SET status = p_status, reviewer_id = v_reviewer_id, reviewer_notes = p_notes, reviewed_at = now()
  WHERE id = p_submission_id
  RETURNING * INTO v_submission;

  IF p_status IN ('passed', 'needs_revision') THEN
    v_outcome := CASE WHEN p_status = 'passed' THEN 'passed' ELSE 'failed' END;
    FOR v_skill_id IN SELECT skill_id FROM public.capstone_skills WHERE capstone_id = v_submission.capstone_id
    LOOP
      PERFORM public.record_skill_evidence(
        v_submission.user_id, v_skill_id, 'capstone', v_outcome, 'capstone', v_submission.capstone_id, NULL, NULL,
        jsonb_build_object('capstone_submission_id', v_submission.id)
      );
    END LOOP;
  END IF;

  PERFORM public.log_audit_event('capstone.submission.reviewed', 'capstone_submission', p_submission_id::text, NULL,
    jsonb_build_object('status', p_status));

  RETURN v_submission;
END;
$$;

REVOKE ALL ON FUNCTION public.review_capstone_submission FROM public;
GRANT EXECUTE ON FUNCTION public.review_capstone_submission TO authenticated, service_role;

-- Status/reviewer fields now change only through the function above -- drop
-- the blanket staff UPDATE policy (no state-transition validation, no
-- audit trail) exactly as scan_findings has no UPDATE policy at all, only
-- transition_scan_finding_status().
DROP POLICY capstone_submissions_update_staff ON public.capstone_submissions;
