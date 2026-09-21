-- ============================================================================
-- Skill Graph (section 4/5): tracks demonstrated ability, not course
-- completion. See docs/adr/0003-skill-graph-state-model.md for the state
-- machine this encodes.
--
-- Critical design rule: skill_evidence and user_skill_states are NEVER
-- directly writable by a client. Evidence is only ever inserted by the
-- grading functions that check a real, server-verified outcome (a quiz
-- graded against hidden correct answers, a lab flag hash compared
-- server-side, an exam scored server-side). See
-- 20260921000010_grading_and_evidence.sql, added alongside the content
-- model these grading functions depend on.
-- ============================================================================

CREATE TABLE public.skill_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0
);

CREATE TABLE public.skills (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  category_id uuid NOT NULL REFERENCES public.skill_categories (id),
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX skills_category_id_idx ON public.skills (category_id);
CREATE INDEX skills_name_trgm_idx ON public.skills USING gin (name gin_trgm_ops);

CREATE TABLE public.skill_prerequisites (
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  prerequisite_skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (skill_id, prerequisite_skill_id),
  CONSTRAINT no_self_prerequisite CHECK (skill_id <> prerequisite_skill_id)
);

-- ----------------------------------------------------------------------------
-- Evidence: one row per graded interaction that speaks to ability with a
-- skill. `evidence_type` corresponds exactly to the "Prove Your Skill"
-- matrix columns in section 5 (theory / quiz / guided lab / unguided lab /
-- ctf / assessment / remediation / retest).
-- ----------------------------------------------------------------------------

CREATE TYPE public.skill_evidence_type AS ENUM (
  'theory',        -- lesson opened AND its comprehension check passed
  'quiz',
  'guided_lab',
  'unguided_lab',
  'ctf',
  'assessment',
  'remediation',    -- fixed a vulnerability they introduced/found
  'retest'          -- re-verified a fix or re-attempted after failing
);

CREATE TYPE public.skill_evidence_outcome AS ENUM ('passed', 'failed', 'partial');

CREATE TABLE public.skill_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Monotonic insertion-order column, independent of `id` (random uuid) and
  -- `occurred_at`. `occurred_at` alone is NOT reliable for "most recent
  -- evidence" ordering: Postgres' now() returns the same value for every
  -- statement in a transaction, so a grading pipeline that records several
  -- evidence rows in one transaction (e.g. a retest immediately following
  -- an assessment) can produce identical occurred_at timestamps. seq
  -- guarantees a deterministic tiebreaker.
  seq bigint GENERATED ALWAYS AS IDENTITY,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  evidence_type public.skill_evidence_type NOT NULL,
  outcome public.skill_evidence_outcome NOT NULL,
  source_type text NOT NULL, -- 'lesson' | 'quiz' | 'lab' | 'ctf_challenge' | 'exam' | 'capstone'
  source_id uuid,
  score numeric,
  hint_level_used smallint CHECK (hint_level_used BETWEEN 0 AND 5),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX skill_evidence_user_skill_idx ON public.skill_evidence (user_id, skill_id, occurred_at DESC, seq DESC);
CREATE INDEX skill_evidence_skill_id_idx ON public.skill_evidence (skill_id);

COMMENT ON TABLE public.skill_evidence IS
  'Append-only, server-authored record of graded interactions. No INSERT '
  'grant exists for authenticated/anon -- rows can only be created by the '
  'SECURITY DEFINER grading functions, which verify the outcome themselves '
  '(hidden quiz answer key, hashed lab flag, server-scored exam) before '
  'writing. A client can never fabricate mastery by inserting a fake row.';

-- ----------------------------------------------------------------------------
-- Derived state: NEVER written directly by clients or by application code
-- outside of public.recompute_skill_state(). It is a materialized summary
-- of skill_evidence, recomputed every time new evidence lands.
-- ----------------------------------------------------------------------------

CREATE TYPE public.skill_state AS ENUM (
  'NOT_STARTED',
  'LEARNING',
  'PRACTICING',
  'ASSESSED',
  'DEMONSTRATED',
  'MASTERED',
  'NEEDS_REVIEW'
);

CREATE TABLE public.user_skill_states (
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  state public.skill_state NOT NULL DEFAULT 'NOT_STARTED',
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, skill_id)
);

CREATE INDEX user_skill_states_user_id_idx ON public.user_skill_states (user_id);

COMMENT ON TABLE public.user_skill_states IS
  'Derived from skill_evidence by public.recompute_skill_state(). No client '
  'write path exists -- see docs/adr/0003-skill-graph-state-model.md.';

-- ----------------------------------------------------------------------------
-- State machine. Documented explicitly rather than left implicit so the
-- rule set can be audited and referenced from the UI copy that explains a
-- user's state (section 5: "you understand the concept but have not yet
-- demonstrated independent practical ability").
--
-- Rules (evaluated top to bottom, first match wins, using ALL evidence for
-- the user+skill so far):
--   NEEDS_REVIEW   if the most recent 'assessment' or 'retest' evidence for
--                   this skill has outcome = 'failed', AND the skill had
--                   previously reached ASSESSED or higher (a regression).
--   MASTERED        passed assessment AND passed (unguided_lab OR ctf) AND
--                   passed retest -- independent ability, formally verified,
--                   and shown to hold up on re-attempt.
--   DEMONSTRATED    passed unguided_lab OR passed ctf -- independent
--                   practical ability without guidance.
--   ASSESSED        passed assessment, but no independent demonstration yet.
--   PRACTICING      passed guided_lab OR passed quiz.
--   LEARNING        passed theory only.
--   NOT_STARTED     no evidence at all.
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
    bool_or(evidence_type = 'assessment' AND outcome = 'passed'),
    bool_or(evidence_type = 'retest' AND outcome = 'passed')
  INTO v_has_theory, v_has_quiz, v_has_guided_lab, v_has_unguided_lab,
       v_has_ctf, v_has_assessment, v_has_retest
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
  ELSIF v_has_assessment AND (v_has_unguided_lab OR v_has_ctf) AND v_has_retest THEN
    v_state := 'MASTERED';
  ELSIF v_has_unguided_lab OR v_has_ctf THEN
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
  ON CONFLICT (user_id, skill_id)
  DO UPDATE SET state = EXCLUDED.state, updated_at = now();

  RETURN v_state;
END;
$$;

COMMENT ON FUNCTION public.recompute_skill_state IS
  'The only writer of user_skill_states. Called by record_skill_evidence() '
  'after every new evidence row. Internal-only (no EXECUTE grant to '
  'authenticated/anon) -- always invoked as part of a grading function.';

-- ----------------------------------------------------------------------------
-- The one function allowed to insert evidence. Internal-only: not granted to
-- authenticated/anon. Content-grading functions (quiz/lab/ctf/exam
-- submission, added in 20260921000010_grading_and_evidence.sql) call this
-- after they have independently verified the outcome.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_skill_evidence(
  p_user_id uuid,
  p_skill_id uuid,
  p_evidence_type public.skill_evidence_type,
  p_outcome public.skill_evidence_outcome,
  p_source_type text,
  p_source_id uuid,
  p_score numeric DEFAULT NULL,
  p_hint_level_used smallint DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.skill_evidence (
    user_id, skill_id, evidence_type, outcome, source_type, source_id,
    score, hint_level_used, metadata
  ) VALUES (
    p_user_id, p_skill_id, p_evidence_type, p_outcome, p_source_type, p_source_id,
    p_score, p_hint_level_used, p_metadata
  ) RETURNING id INTO v_id;

  PERFORM public.recompute_skill_state(p_user_id, p_skill_id);

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_skill_evidence FROM public;
REVOKE ALL ON FUNCTION public.recompute_skill_state FROM public;
-- Deliberately no GRANT to authenticated: only other SECURITY DEFINER
-- functions owned by this same (superuser) role can call these, and
-- service_role (BYPASSRLS) is granted explicitly for server-side batch use.
GRANT EXECUTE ON FUNCTION public.record_skill_evidence TO service_role;
GRANT EXECUTE ON FUNCTION public.recompute_skill_state TO service_role;

CREATE TRIGGER skills_set_updated_at
  BEFORE UPDATE ON public.skills
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
