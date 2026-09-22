-- ============================================================================
-- Lab terminal RLS regression tests:
--  - lab_environments (the authored virtual filesystem/flag content) is
--    NEVER selectable by a non-staff session, mirroring lab_flags -- this
--    is what makes "the client never receives the environment spec
--    directly" (ADR 0009) a real, tested guarantee, not just a claim.
--  - lab_terminal_commands (the transcript) is owner-scoped, insertable
--    only for a lab_instance the caller actually owns, immutable once
--    written.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local');
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '33333333-3333-3333-3333-333333333333';
INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-3333-3333-333333333333', 'admin')
  ON CONFLICT DO NOTHING;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- Fixtures created as postgres (superuser, bypasses RLS), mirroring how
-- 005_seeded_content_e2e.sql sets up staff-only content -- a real learner
-- session never reads lab_environments directly, only through the server
-- execution path this test suite can't invoke without a live Next.js
-- process, so these tests focus on the RLS boundary itself.
DO $$
DECLARE
  v_lab_id uuid;
  v_instance_id uuid;
BEGIN
  INSERT INTO public.labs (slug, title, category, difficulty, published)
  VALUES ('test-terminal-lab', 'Test Terminal Lab', 'linux', 'easy', true)
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_environments (lab_id, variant_seed, spec)
  VALUES (v_lab_id, 0, jsonb_build_object(
    'hostname', 'test01',
    'initial_cwd', '/home/user',
    'filesystem', jsonb_build_object(
      '/home/user/flag.txt', jsonb_build_object('type', 'file', 'content', 'ICOREPEN{terminal_test}')
    )
  ));

  INSERT INTO public.lab_instances (lab_id, user_id, guided, status)
  VALUES (v_lab_id, '11111111-1111-1111-1111-111111111111', true, 'running')
  RETURNING id INTO v_instance_id;

  INSERT INTO public.labs (slug, title, category, difficulty, published)
  VALUES ('test-no-terminal-lab', 'Test Lab Without a Terminal', 'linux', 'easy', true);
END $$;

-- ============================================================================
-- 0. labs.has_terminal is kept accurate by trigger -- true only for the lab
--    with an authored environment, and readable by anyone (it reveals no
--    secret content, unlike lab_environments itself).
-- ============================================================================
DO $$
DECLARE v_has_terminal boolean; v_has_terminal_other boolean;
BEGIN
  SELECT has_terminal INTO v_has_terminal FROM public.labs WHERE slug = 'test-terminal-lab';
  SELECT has_terminal INTO v_has_terminal_other FROM public.labs WHERE slug = 'test-no-terminal-lab';
  IF v_has_terminal IS NOT true THEN RAISE EXCEPTION 'FAIL: has_terminal should be true for a lab with an environment'; END IF;
  IF v_has_terminal_other IS NOT false THEN RAISE EXCEPTION 'FAIL: has_terminal should be false for a lab without one'; END IF;
  RAISE NOTICE 'PASS: labs.has_terminal is kept accurate by trigger';
END $$;

-- ============================================================================
-- 1. Alice (a plain authenticated user, not staff) cannot read
--    lab_environments at all -- not her own lab's, not anyone's.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.lab_environments;
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: a non-staff user can read lab_environments (% rows)', cnt; END IF;
  RAISE NOTICE 'PASS: lab_environments is never selectable by a non-staff session';
END $$;

-- ============================================================================
-- 2. Staff CAN read lab_environments (needed to author/review it).
--    Scoped to this test's own fixture lab, not a bare count(*), since
--    real seeded content (supabase/migrations/20260922000007_seed_terminal_lab.sql)
--    also has a lab_environments row and this test shouldn't be coupled to
--    exactly how much of that exists.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.lab_environments le
    JOIN public.labs l ON l.id = le.lab_id
    WHERE l.slug = 'test-terminal-lab';
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: staff should see 1 lab_environments row for the test lab, saw %', cnt; END IF;
  RAISE NOTICE 'PASS: staff can read lab_environments';
END $$;

-- ============================================================================
-- 3. Alice can insert a terminal command transcript row for her own
--    running lab instance.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_instance_id uuid;
BEGIN
  SELECT id INTO v_instance_id FROM public.lab_instances WHERE user_id = '11111111-1111-1111-1111-111111111111';
  INSERT INTO public.lab_terminal_commands (lab_instance_id, user_id, command, output, cwd_before, cwd_after)
  VALUES (v_instance_id, '11111111-1111-1111-1111-111111111111', 'pwd', '/home/user', '/home/user', '/home/user');
  RAISE NOTICE 'PASS: alice can insert a command transcript for her own lab instance';
END $$;

-- ============================================================================
-- 4. Bob cannot insert a transcript row for Alice's lab instance, even
--    claiming his own user_id (the instance-ownership check must catch
--    this, not just user_id = auth.uid()).
-- ============================================================================
DO $$
DECLARE v_alice_instance_id uuid;
BEGIN
  RESET ROLE;
  SELECT id INTO v_alice_instance_id FROM public.lab_instances WHERE user_id = '11111111-1111-1111-1111-111111111111';
  CALL test_act_as('22222222-2222-2222-2222-222222222222');

  BEGIN
    INSERT INTO public.lab_terminal_commands (lab_instance_id, user_id, command, output, cwd_before, cwd_after)
    VALUES (v_alice_instance_id, '22222222-2222-2222-2222-222222222222', 'cat flag.txt', 'ICOREPEN{terminal_test}', '/home/user', '/home/user');
    RAISE EXCEPTION 'FAIL: bob inserted a transcript row into alice''s lab instance';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot insert a transcript row into another user''s lab instance (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 5. Bob cannot read Alice's transcript; staff can.
-- ============================================================================
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.lab_terminal_commands WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s command transcript'; END IF;
  RAISE NOTICE 'PASS: another user cannot read alice''s command transcript';
END $$;

CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.lab_terminal_commands WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: staff should see alice''s 1 command, saw %', cnt; END IF;
  RAISE NOTICE 'PASS: staff can read any user''s command transcript';
END $$;

-- ============================================================================
-- 6. Transcript rows are immutable -- no UPDATE policy, even for staff.
-- ============================================================================
DO $$
DECLARE affected int;
BEGIN
  BEGIN
    UPDATE public.lab_terminal_commands SET output = 'tampered' WHERE user_id = '11111111-1111-1111-1111-111111111111';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN RAISE EXCEPTION 'FAIL: staff edited a command transcript (% rows)', affected; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS: command transcripts are immutable, even for staff';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL LAB TERMINAL RLS TESTS PASSED'
