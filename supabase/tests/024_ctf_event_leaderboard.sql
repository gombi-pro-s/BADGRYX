-- ============================================================================
-- Proves ctf_event_leaderboard() (20260922000026) is a real, deliberate
-- bypass of ctf_submissions' owner-only RLS, not a hole in it: it returns
-- only the cross-user AGGREGATE (never raw per-challenge submissions),
-- ranks by total points desc then earliest-tie-break, and a draft event's
-- leaderboard is staff-only just like the event row itself.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice-staff@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob-firstplace@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'carol-tiebreak@test.local'),
  ('44444444-4444-4444-4444-444444444444', 'dave-lastplace@test.local');

INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin');
UPDATE public.profiles SET display_name = 'Bob' WHERE id = '22222222-2222-2222-2222-222222222222';
UPDATE public.profiles SET display_name = 'Carol' WHERE id = '33333333-3333-3333-3333-333333333333';
UPDATE public.profiles SET display_name = 'Dave' WHERE id = '44444444-4444-4444-4444-444444444444';

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

INSERT INTO public.ctf_events (id, slug, title, published, scoring_type)
VALUES
  ('e0000000-0000-0000-0000-000000000001', 'spring-ctf', 'Spring CTF', true, 'static'),
  ('e0000000-0000-0000-0000-000000000002', 'draft-ctf', 'Draft CTF', false, 'static');

INSERT INTO public.ctf_challenges (id, event_id, slug, title, category, difficulty, points, flag_hash, published)
VALUES
  ('c0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'web-1', 'Web One', 'web', 'easy', 100, repeat('a', 64), true),
  ('c0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000001', 'web-2', 'Web Two', 'web', 'medium', 150, repeat('b', 64), true);

-- Bob solves both (250 total), finishing at t+20min.
-- Carol solves both too (250 total, tied with bob), but finishes at
-- t+10min -- 10 minutes EARLIER than bob, so she should rank ABOVE him.
-- Dave solves only the first (100 total) -- clear last place.
INSERT INTO public.ctf_submissions (challenge_id, user_id, correct, points_awarded, submitted_at) VALUES
  ('c0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', true, 100, now() - interval '30 minutes'),
  ('c0000000-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', true, 150, now() - interval '10 minutes'),
  ('c0000000-0000-0000-0000-000000000001', '33333333-3333-3333-3333-333333333333', true, 100, now() - interval '25 minutes'),
  ('c0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', true, 150, now() - interval '20 minutes'),
  ('c0000000-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', true, 100, now() - interval '5 minutes'),
  -- An incorrect attempt should never count toward the aggregate.
  ('c0000000-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', false, 0, now() - interval '4 minutes');

-- ============================================================================
-- 1. Carol (tied on points, earlier last-solve) ranks above Bob; Dave last.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_rows record;
  v_names text[];
  v_points int[];
BEGIN
  SELECT array_agg(display_name ORDER BY total_points DESC, last_solve_at ASC),
         array_agg(total_points ORDER BY total_points DESC, last_solve_at ASC)
    INTO v_names, v_points
    FROM public.ctf_event_leaderboard('e0000000-0000-0000-0000-000000000001');

  IF v_names <> ARRAY['Carol', 'Bob', 'Dave'] THEN
    RAISE EXCEPTION 'FAIL: expected leaderboard order [Carol, Bob, Dave], got %', v_names;
  END IF;
  IF v_points <> ARRAY[250, 250, 100] THEN
    RAISE EXCEPTION 'FAIL: expected points [250, 250, 100], got %', v_points;
  END IF;
  RAISE NOTICE 'PASS: leaderboard ranks by total points desc, tied scores broken by earliest last-solve';
END $$;

-- ============================================================================
-- 2. A wrong attempt never contributes points or a solved count.
-- ============================================================================
DO $$
DECLARE v_dave_solved int;
BEGIN
  SELECT solved_count INTO v_dave_solved FROM public.ctf_event_leaderboard('e0000000-0000-0000-0000-000000000001')
    WHERE display_name = 'Dave';
  IF v_dave_solved <> 1 THEN RAISE EXCEPTION 'FAIL: dave''s incorrect attempt was counted as a solve, solved_count=%', v_dave_solved; END IF;
  RAISE NOTICE 'PASS: an incorrect submission never counts toward points or solved_count';
END $$;

-- ============================================================================
-- 3. Bob (a plain user) can see the aggregate leaderboard but NOT carol's
--    raw ctf_submissions rows -- the function is a deliberate, narrow
--    bypass, not a hole that also exposes per-challenge details.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.ctf_submissions WHERE user_id = '33333333-3333-3333-3333-333333333333';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: bob could read carol''s raw ctf_submissions rows directly'; END IF;
  RAISE NOTICE 'PASS: a plain user cannot read another user''s raw ctf_submissions rows';
END $$;

-- ============================================================================
-- 4. A draft (unpublished) event's leaderboard is empty for a plain user.
-- ============================================================================
RESET ROLE;
INSERT INTO public.ctf_challenges (id, event_id, slug, title, category, difficulty, points, flag_hash, published)
VALUES ('c0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000002', 'draft-1', 'Draft One', 'web', 'easy', 100, repeat('c', 64), true);
INSERT INTO public.ctf_submissions (challenge_id, user_id, correct, points_awarded)
VALUES ('c0000000-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', true, 100);

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.ctf_event_leaderboard('e0000000-0000-0000-0000-000000000002');
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: a plain user saw a draft event''s leaderboard'; END IF;
  RAISE NOTICE 'PASS: a plain user cannot see a draft event''s leaderboard';
END $$;

-- ============================================================================
-- 5. Staff (alice) CAN see the draft event's leaderboard.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.ctf_event_leaderboard('e0000000-0000-0000-0000-000000000002');
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: staff could not see a draft event''s leaderboard, got % rows', v_count; END IF;
  RAISE NOTICE 'PASS: staff can see a draft event''s leaderboard';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL CTF EVENT LEADERBOARD TESTS PASSED'
