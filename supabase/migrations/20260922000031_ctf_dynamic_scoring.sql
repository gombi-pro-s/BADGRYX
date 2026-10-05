-- ============================================================================
-- Dynamic CTF scoring: `ctf_events.scoring_type = 'dynamic'` has existed
-- since the original content model (20260921000008) and the admin UI has
-- let staff pick it since ADR 0021 -- but `submit_ctf_flag()` always
-- copied `ctf_challenges.points` flatly regardless of scoring type, and
-- both admin event forms disclosed as much ("picking it stores the
-- intent but challenges still score at their fixed points"). This
-- migration makes it real.
--
-- Design: standard CTFd-style dynamic scoring -- each challenge decays
-- linearly from its `points` (max/initial value) down to a floor as more
-- competitors solve it, and each solver's own `points_awarded` is frozen
-- at whatever the value was the moment THEY solved it (not recomputed
-- later), which `ctf_submissions.points_awarded` and
-- `ctf_event_leaderboard()` (20260922000026, sums `points_awarded`)
-- already support structurally -- neither needs to change.
--
-- The floor is `ctf_challenges.min_points` (new column below), defaulting
-- to half of `points` when left unset so already-seeded challenges don't
-- need a backfill to behave sensibly the moment an event's scoring_type
-- flips to 'dynamic'. Decay is linear over the first 10 solves, then
-- flat at the floor -- a fixed, documented constant rather than a
-- per-challenge decay-rate knob, since that's the one extra piece of
-- state this feature actually needs beyond a floor.
-- ============================================================================

ALTER TABLE public.ctf_challenges
  ADD COLUMN min_points integer,
  ADD CONSTRAINT ctf_challenges_min_points_range
    CHECK (min_points IS NULL OR (min_points >= 0 AND min_points <= points));

COMMENT ON COLUMN public.ctf_challenges.min_points IS
  'Decay floor for dynamic-scoring events. NULL defaults to half of points (see ctf_challenge_current_points()). Unused for static-scoring events and for challenges with no event_id.';

-- ----------------------------------------------------------------------------
-- ctf_challenge_current_points: the single source of truth for "how many
-- points does solving this challenge award right now." Both
-- `ctf_challenges_public` (what learners see before solving) and
-- `submit_ctf_flag()` (what actually gets awarded) call this, so the two
-- can never disagree. SECURITY DEFINER because it reads `ctf_challenges`
-- (staff-only RLS) and `ctf_submissions` (owner-only RLS) across users to
-- get a solve count -- the same "one function is the narrow, deliberate
-- exception to row ownership" reasoning as ctf_event_leaderboard().
-- Returns a solve COUNT only, same privacy shape as the leaderboard: never
-- which specific user solved it.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.ctf_challenge_current_points(p_challenge_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_challenge public.ctf_challenges;
  v_scoring_type public.ctf_scoring_type;
  v_solved_count integer;
  v_min_points integer;
  v_decay_solves constant integer := 10;
  v_step numeric;
BEGIN
  SELECT * INTO v_challenge FROM public.ctf_challenges WHERE id = p_challenge_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Independent challenges (no event) and static-scoring events always
  -- score at the flat, fixed value -- the behavior every challenge had
  -- before this migration.
  IF v_challenge.event_id IS NULL THEN
    RETURN v_challenge.points;
  END IF;

  SELECT scoring_type INTO v_scoring_type FROM public.ctf_events WHERE id = v_challenge.event_id;
  IF v_scoring_type IS DISTINCT FROM 'dynamic' THEN
    RETURN v_challenge.points;
  END IF;

  v_min_points := coalesce(v_challenge.min_points, v_challenge.points / 2);
  IF v_challenge.points <= v_min_points THEN
    RETURN v_challenge.points;
  END IF;

  SELECT count(*) INTO v_solved_count
    FROM public.ctf_submissions
    WHERE challenge_id = p_challenge_id AND correct = true;

  -- Linear decay from `points` to `min_points` over the first
  -- `v_decay_solves` solves; flat at the floor afterward. The Nth solver
  -- (0-indexed, so the FIRST solver sees v_solved_count = 0 and gets the
  -- full value) sees `points - step * min(N, v_decay_solves)`.
  v_step := (v_challenge.points - v_min_points)::numeric / v_decay_solves;
  RETURN greatest(
    v_min_points,
    round(v_challenge.points - v_step * least(v_solved_count, v_decay_solves))
  )::integer;
END;
$$;

REVOKE ALL ON FUNCTION public.ctf_challenge_current_points FROM public;
GRANT EXECUTE ON FUNCTION public.ctf_challenge_current_points TO anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- ctf_challenges_public: add `current_points` alongside the existing
-- `points` column (kept as-is -- it's the max/initial value, still useful
-- for admins and for static challenges where the two are always equal).
-- Learner-facing pages should display `current_points`, which is always
-- correct for every scoring type since it only ever differs from `points`
-- when a dynamic event's challenge has actually decayed.
-- ----------------------------------------------------------------------------

-- CREATE OR REPLACE VIEW only allows new columns to be appended at the end
-- (it cannot reorder or insert mid-list), so `current_points` goes after
-- the original `published` column rather than next to `points`.
CREATE OR REPLACE VIEW public.ctf_challenges_public AS
  SELECT
    id, event_id, lab_id, slug, title, description, category, difficulty,
    points, published, public.ctf_challenge_current_points(id) AS current_points
  FROM public.ctf_challenges
  WHERE published = true;

GRANT SELECT ON public.ctf_challenges_public TO anon, authenticated;

-- ----------------------------------------------------------------------------
-- submit_ctf_flag: the only change from the original (20260921000010) is
-- the points computation on a correct, first-time solve -- was a flat
-- `v_challenge.points` copy, now `ctf_challenge_current_points()`, called
-- BEFORE this solve's own INSERT so the solve count it sees doesn't
-- include itself (the first solver's count is 0, giving them the max
-- value). Everything else -- auth check, already-solved idempotent
-- return, flag hash comparison, skill evidence recording, audit log --
-- is unchanged.
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
    -- Computed BEFORE the INSERT below, so the solve count this sees
    -- never includes this submission -- the Nth solver's own flag
    -- submission always scores based on however many solves existed
    -- before theirs.
    v_points := public.ctf_challenge_current_points(p_challenge_id);
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
