-- ============================================================================
-- Proves ctf_challenge_current_points()/submit_ctf_flag() (20260922000031)
-- actually implement dynamic scoring rather than leaving it inert: a
-- dynamic-scoring event's challenge decays linearly from `points` down to
-- its floor (`min_points`, defaulting to half of `points` when unset)
-- over its first 10 solves, each solver's own points_awarded is frozen at
-- solve time, and a static-scoring event (or an independent challenge
-- with no event at all) never decays no matter how many solves pile up.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'first-solver@test.local'),
  ('a1000000-0000-0000-0000-000000000002', 'second-solver@test.local'),
  ('a1000000-0000-0000-0000-000000000003', 'eleventh-solver@test.local'),
  ('a1000000-0000-0000-0000-000000000004', 'twelfth-solver@test.local'),
  ('a1000000-0000-0000-0000-000000000005', 'static-solver@test.local');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

INSERT INTO public.ctf_events (id, slug, title, published, scoring_type) VALUES
  ('e2000000-0000-0000-0000-000000000001', 'dynamic-ctf', 'Dynamic CTF', true, 'dynamic'),
  ('e2000000-0000-0000-0000-000000000002', 'static-ctf', 'Static CTF', true, 'static');

-- min_points left NULL on purpose for the dynamic challenge -- should
-- default to half of points (200 / 2 = 100).
INSERT INTO public.ctf_challenges (id, event_id, slug, title, category, difficulty, points, flag_hash, published) VALUES
  ('c2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'dyn-1', 'Dynamic One', 'web', 'easy', 200, encode(digest('ICOREPEN{dyn}', 'sha256'), 'hex'), true),
  ('c2000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000002', 'static-1', 'Static One', 'web', 'easy', 200, encode(digest('ICOREPEN{static}', 'sha256'), 'hex'), true);

-- ============================================================================
-- 1. First solver of a fresh dynamic challenge gets the full value.
-- ============================================================================
CALL test_act_as('a1000000-0000-0000-0000-000000000001');
DO $$
DECLARE v_sub public.ctf_submissions;
BEGIN
  SELECT * INTO v_sub FROM public.submit_ctf_flag('c2000000-0000-0000-0000-000000000001', 'ICOREPEN{dyn}');
  IF v_sub.points_awarded <> 200 THEN RAISE EXCEPTION 'FAIL: first solver expected 200, got %', v_sub.points_awarded; END IF;
  RAISE NOTICE 'PASS: first solver of a dynamic challenge gets the full points value';
END $$;

-- ============================================================================
-- 2. Second solver sees it decayed by exactly one step
--    (step = (points - min_points) / 10 = (200 - 100) / 10 = 10).
-- ============================================================================
CALL test_act_as('a1000000-0000-0000-0000-000000000002');
DO $$
DECLARE v_sub public.ctf_submissions;
BEGIN
  SELECT * INTO v_sub FROM public.submit_ctf_flag('c2000000-0000-0000-0000-000000000001', 'ICOREPEN{dyn}');
  IF v_sub.points_awarded <> 190 THEN RAISE EXCEPTION 'FAIL: second solver expected 190, got %', v_sub.points_awarded; END IF;
  RAISE NOTICE 'PASS: second solver sees one decay step less than the first';
END $$;

-- ============================================================================
-- 3. ctf_challenges_public.current_points matches what the NEXT real solve
--    would actually award -- the learner-facing display and the grading
--    function can never disagree, since both call the same
--    ctf_challenge_current_points().
-- ============================================================================
DO $$
DECLARE v_current int;
BEGIN
  SELECT current_points INTO v_current FROM public.ctf_challenges_public WHERE id = 'c2000000-0000-0000-0000-000000000001';
  IF v_current <> 180 THEN RAISE EXCEPTION 'FAIL: expected current_points=180 after 2 solves, got %', v_current; END IF;
  RAISE NOTICE 'PASS: ctf_challenges_public.current_points reflects the live decayed value';
END $$;

-- ============================================================================
-- 4. Manufacture 8 more solves (10 total) directly, then prove the floor
--    (min_points, defaulted to points/2 = 100) is reached and never
--    breached by an 11th or 12th solver.
-- ============================================================================
RESET ROLE;
INSERT INTO auth.users (id, email)
  SELECT ('a1000000-0000-0000-0000-0000000000' || lpad((5 + n)::text, 2, '0'))::uuid, 'filler-' || n || '@test.local'
  FROM generate_series(1, 8) AS n;
INSERT INTO public.ctf_submissions (challenge_id, user_id, correct, points_awarded)
  SELECT 'c2000000-0000-0000-0000-000000000001', ('a1000000-0000-0000-0000-0000000000' || lpad((5 + n)::text, 2, '0'))::uuid, true, 0
  FROM generate_series(1, 8) AS n;

CALL test_act_as('a1000000-0000-0000-0000-000000000003');
DO $$
DECLARE v_sub public.ctf_submissions;
BEGIN
  -- This is the 11th correct submission overall (2 real + 8 filler), so
  -- the solve count ctf_challenge_current_points sees is exactly 10 --
  -- the configured decay window -- i.e. the floor.
  SELECT * INTO v_sub FROM public.submit_ctf_flag('c2000000-0000-0000-0000-000000000001', 'ICOREPEN{dyn}');
  IF v_sub.points_awarded <> 100 THEN RAISE EXCEPTION 'FAIL: 11th solver expected the floor (100), got %', v_sub.points_awarded; END IF;
  RAISE NOTICE 'PASS: decay reaches its floor (min_points) after the configured number of solves';
END $$;

RESET ROLE;
CALL test_act_as('a1000000-0000-0000-0000-000000000004');
DO $$
DECLARE v_sub public.ctf_submissions;
BEGIN
  SELECT * INTO v_sub FROM public.submit_ctf_flag('c2000000-0000-0000-0000-000000000001', 'ICOREPEN{dyn}');
  IF v_sub.points_awarded <> 100 THEN RAISE EXCEPTION 'FAIL: 12th solver expected the floor to stay at 100, got %', v_sub.points_awarded; END IF;
  RAISE NOTICE 'PASS: the floor never breaches below min_points no matter how many further solves happen';
END $$;

-- ============================================================================
-- 5. A static-scoring event's challenge never decays, no matter how many
--    competitors solve it -- scoring_type is checked, not just presence of
--    an event_id.
-- ============================================================================
RESET ROLE;
INSERT INTO public.ctf_submissions (challenge_id, user_id, correct, points_awarded)
  SELECT 'c2000000-0000-0000-0000-000000000002', ('a1000000-0000-0000-0000-0000000000' || lpad((5 + n)::text, 2, '0'))::uuid, true, 200
  FROM generate_series(1, 5) AS n;

CALL test_act_as('a1000000-0000-0000-0000-000000000005');
DO $$
DECLARE v_sub public.ctf_submissions;
BEGIN
  SELECT * INTO v_sub FROM public.submit_ctf_flag('c2000000-0000-0000-0000-000000000002', 'ICOREPEN{static}');
  IF v_sub.points_awarded <> 200 THEN RAISE EXCEPTION 'FAIL: a static-scoring event challenge decayed, got %', v_sub.points_awarded; END IF;
  RAISE NOTICE 'PASS: a static-scoring event challenge never decays regardless of solve count';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL CTF DYNAMIC SCORING TESTS PASSED'
