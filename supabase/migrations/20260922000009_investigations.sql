-- ============================================================================
-- OSINT / Digital Forensics investigation workspace (section 17/section
-- OSINT-Forensics): a content type parallel to labs/CTF challenges. A
-- learner reviews a case's real (synthetic-but-realistic) evidence
-- artifacts -- WHOIS records, email headers, log excerpts, chat
-- transcripts -- and answers structured questions about what actually
-- happened, graded deterministically server-side, exactly like every other
-- grading pipeline in this app (never "an AI decided you got it right").
--
-- Artifacts are text-based, presented honestly as what they are (a WHOIS
-- record, a header dump) -- this is NOT claiming to do real image/file
-- forensics (EXIF extraction, PCAP parsing, etc.), which is out of scope;
-- see RELEASE_CHECKLIST.md for what's actually built vs. still ahead.
-- ============================================================================

CREATE TYPE public.investigation_artifact_type AS ENUM (
  'whois_record', 'email_headers', 'social_media_profile', 'file_metadata',
  'log_excerpt', 'network_capture_summary', 'document_excerpt', 'chat_transcript'
);
CREATE TYPE public.investigation_question_type AS ENUM ('exact_text', 'multiple_choice');

-- 'investigation' evidence is independent demonstration -- a learner
-- correctly answering real investigative questions with no guidance is the
-- same category of "practical ability without hand-holding" as an
-- unguided lab or a CTF solve. See recompute_skill_state() below, updated
-- to treat it identically to those two for reaching DEMONSTATED/MASTERED.
ALTER TYPE public.skill_evidence_type ADD VALUE 'investigation';

CREATE TABLE public.investigations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  briefing text,
  category public.lab_category NOT NULL,
  difficulty public.difficulty_level NOT NULL,
  objectives jsonb NOT NULL DEFAULT '[]'::jsonb,
  estimated_minutes integer NOT NULL DEFAULT 45,
  points integer NOT NULL DEFAULT 100,
  passing_score integer NOT NULL DEFAULT 70,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER investigations_set_updated_at
  BEFORE UPDATE ON public.investigations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.investigation_skills (
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (investigation_id, skill_id)
);

-- Artifacts are the public case evidence -- visible to anyone who can see
-- the published investigation, same as a CTF challenge's description. They
-- are not a secret; what's secret is the correct answer (below).
CREATE TABLE public.investigation_artifacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  artifact_type public.investigation_artifact_type NOT NULL,
  title text NOT NULL,
  content text NOT NULL,
  order_index integer NOT NULL DEFAULT 0
);

CREATE INDEX investigation_artifacts_investigation_id_idx ON public.investigation_artifacts (investigation_id);

-- Correctness lives only here (answer_hash / investigation_choices.is_correct).
-- Never directly selectable by authenticated/anon -- learners read via
-- investigation_questions_for_attempt below, the same pattern
-- quiz_questions_for_attempt already established.
CREATE TABLE public.investigation_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  question_text text NOT NULL,
  question_type public.investigation_question_type NOT NULL,
  order_index integer NOT NULL DEFAULT 0,
  points numeric NOT NULL DEFAULT 1,
  -- sha256(lower(trim(correct answer))) -- only set for exact_text
  -- questions; NULL for multiple_choice (correctness lives in
  -- investigation_choices instead). Normalized so "203.0.113.7" and
  -- " 203.0.113.7 " both hash the same, matching how a learner would
  -- naturally type an investigative answer.
  answer_hash text,
  CONSTRAINT investigation_questions_answer_hash_matches_type CHECK (
    (question_type = 'exact_text' AND answer_hash IS NOT NULL)
    OR (question_type = 'multiple_choice' AND answer_hash IS NULL)
  )
);

CREATE INDEX investigation_questions_investigation_id_idx ON public.investigation_questions (investigation_id);

CREATE TABLE public.investigation_choices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL REFERENCES public.investigation_questions (id) ON DELETE CASCADE,
  choice_text text NOT NULL,
  is_correct boolean NOT NULL DEFAULT false,
  order_index integer NOT NULL DEFAULT 0
);

CREATE INDEX investigation_choices_question_id_idx ON public.investigation_choices (question_id);

CREATE VIEW public.investigation_questions_for_attempt
AS
  SELECT
    i.id AS investigation_id, i.slug, i.title, i.passing_score,
    iq.id AS question_id, iq.question_text, iq.question_type, iq.order_index, iq.points,
    ic.id AS choice_id, ic.choice_text, ic.order_index AS choice_order_index
  FROM public.investigations i
  JOIN public.investigation_questions iq ON iq.investigation_id = i.id
  LEFT JOIN public.investigation_choices ic ON ic.question_id = iq.id
  WHERE i.published = true;

CREATE TABLE public.investigation_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  notes text NOT NULL DEFAULT '',
  started_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (investigation_id, user_id),
  CONSTRAINT investigation_instances_notes_bounded CHECK (char_length(notes) <= 20000)
);

CREATE TRIGGER investigation_instances_set_updated_at
  BEFORE UPDATE ON public.investigation_instances
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN public.investigation_instances.notes IS
  'A personal, owner-only scratchpad for the learner''s own working notes '
  'while investigating -- not graded, not shown to anyone else (not even '
  'staff support access, unlike most other owner-scoped tables in this '
  'app, since these are genuinely private working notes rather than '
  'evidence of anything).';

CREATE TABLE public.investigation_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  answers jsonb NOT NULL,
  score numeric NOT NULL,
  passed boolean NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX investigation_submissions_user_id_idx ON public.investigation_submissions (user_id, submitted_at DESC);

-- ----------------------------------------------------------------------------
-- recompute_skill_state(): re-declared with 'investigation' added
-- everywhere 'unguided_lab'/'ctf' already appear -- independent evidence,
-- same weight in the state machine. Everything else is identical to
-- 20260921000006_skill_graph.sql; this is a straight CREATE OR REPLACE.
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
    bool_or(evidence_type = 'assessment' AND outcome = 'passed'),
    bool_or(evidence_type = 'retest' AND outcome = 'passed')
  INTO v_has_theory, v_has_quiz, v_has_guided_lab, v_has_unguided_lab,
       v_has_ctf, v_has_investigation, v_has_assessment, v_has_retest
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
  ELSIF v_has_assessment AND (v_has_unguided_lab OR v_has_ctf OR v_has_investigation) AND v_has_retest THEN
    v_state := 'MASTERED';
  ELSIF v_has_unguided_lab OR v_has_ctf OR v_has_investigation THEN
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
-- submit_investigation_answers(): grades multiple_choice against
-- investigation_choices.is_correct (set-equality, same as
-- submit_quiz_attempt) and exact_text against
-- investigation_questions.answer_hash (normalized sha256, same idea as
-- submit_lab_flag's flag_hash comparison). Records skill_evidence.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_investigation_answers(
  p_investigation_id uuid,
  p_answers jsonb -- {"<question_id>": ["<choice_id>", ...] | "<exact text answer>"}
)
  RETURNS public.investigation_submissions
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_investigation public.investigations;
  v_total_points numeric := 0;
  v_earned_points numeric := 0;
  v_question record;
  v_selected uuid[];
  v_correct_ids uuid[];
  v_submitted_text text;
  v_submission public.investigation_submissions;
  v_skill_id uuid;
  v_outcome public.skill_evidence_outcome;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_investigation FROM public.investigations WHERE id = p_investigation_id AND published = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'investigation not found or not published' USING ERRCODE = 'P0002';
  END IF;

  FOR v_question IN
    SELECT id, question_type, points, answer_hash FROM public.investigation_questions WHERE investigation_id = p_investigation_id
  LOOP
    v_total_points := v_total_points + v_question.points;

    IF v_question.question_type = 'multiple_choice' THEN
      SELECT array_agg(id) INTO v_correct_ids
        FROM public.investigation_choices WHERE question_id = v_question.id AND is_correct = true;

      SELECT array(
        SELECT jsonb_array_elements_text(
          COALESCE(p_answers -> v_question.id::text, '[]'::jsonb)
        )::uuid
      ) INTO v_selected;

      IF v_selected IS NOT NULL AND v_correct_ids IS NOT NULL
         AND v_selected @> v_correct_ids AND v_correct_ids @> v_selected THEN
        v_earned_points := v_earned_points + v_question.points;
      END IF;
    ELSE
      v_submitted_text := p_answers ->> v_question.id::text;
      IF v_submitted_text IS NOT NULL
         AND encode(digest(lower(trim(v_submitted_text)), 'sha256'), 'hex') = v_question.answer_hash THEN
        v_earned_points := v_earned_points + v_question.points;
      END IF;
    END IF;
  END LOOP;

  INSERT INTO public.investigation_submissions (investigation_id, user_id, answers, score, passed)
  VALUES (
    p_investigation_id, v_user_id, p_answers,
    CASE WHEN v_total_points > 0 THEN round(v_earned_points / v_total_points * 100, 2) ELSE 0 END,
    (CASE WHEN v_total_points > 0 THEN (v_earned_points / v_total_points * 100) ELSE 0 END) >= v_investigation.passing_score
  )
  RETURNING * INTO v_submission;

  v_outcome := CASE WHEN v_submission.passed THEN 'passed' ELSE 'failed' END;

  FOR v_skill_id IN SELECT skill_id FROM public.investigation_skills WHERE investigation_id = p_investigation_id
  LOOP
    PERFORM public.record_skill_evidence(
      v_user_id, v_skill_id, 'investigation', v_outcome, 'investigation', p_investigation_id, v_submission.score, NULL,
      jsonb_build_object('investigation_submission_id', v_submission.id)
    );
  END LOOP;

  PERFORM public.log_audit_event('investigation.answers.submitted', 'investigation', p_investigation_id::text, NULL,
    jsonb_build_object('passed', v_submission.passed, 'score', v_submission.score));

  RETURN v_submission;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_investigation_answers FROM public;
GRANT EXECUTE ON FUNCTION public.submit_investigation_answers TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------

ALTER TABLE public.investigations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigations FORCE ROW LEVEL SECURITY;
CREATE POLICY investigations_select_published_or_staff ON public.investigations
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY investigations_staff_write ON public.investigations
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.investigation_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_skills FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_skills_select_all ON public.investigation_skills FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY investigation_skills_staff_write ON public.investigation_skills
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.investigation_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_artifacts FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_artifacts_select_published_or_staff ON public.investigation_artifacts
  FOR SELECT TO anon, authenticated
  USING (
    public.is_staff()
    OR EXISTS (SELECT 1 FROM public.investigations i WHERE i.id = investigation_id AND i.published = true)
  );
CREATE POLICY investigation_artifacts_staff_write ON public.investigation_artifacts
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- Questions/choices: staff-only direct access (hides answer_hash/is_correct).
-- Learners read via investigation_questions_for_attempt.
ALTER TABLE public.investigation_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_questions FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_questions_staff_only ON public.investigation_questions
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.investigation_choices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_choices FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_choices_staff_only ON public.investigation_choices
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

GRANT SELECT ON public.investigation_questions_for_attempt TO anon, authenticated;

ALTER TABLE public.investigation_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_instances FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_instances_select_own ON public.investigation_instances
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY investigation_instances_insert_own ON public.investigation_instances
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY investigation_instances_update_own ON public.investigation_instances
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
-- Deliberately no staff-read policy on this one table (unlike almost every
-- other owner-scoped table in this app) -- see the column comment above:
-- these are genuinely private working notes, not evidence or a support
-- surface.

ALTER TABLE public.investigation_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_submissions FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_submissions_select_own_or_staff ON public.investigation_submissions
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff());
-- No INSERT policy: writes only via submit_investigation_answers().
