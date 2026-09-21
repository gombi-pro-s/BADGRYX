-- ============================================================================
-- Skill Graph regression tests: evidence is unforgeable, state machine is
-- computed correctly and matches the section-5 "Prove Your Skill" semantics.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local');

INSERT INTO public.skill_categories (id, slug, name) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'web-vulns', 'Web Vulnerabilities');

INSERT INTO public.skills (id, slug, name, category_id) VALUES
  ('50000000-0000-0000-0000-000000000001', 'test-sql-injection', 'SQL Injection', 'c0000000-0000-0000-0000-000000000001');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CREATE OR REPLACE PROCEDURE test_act_as_service() LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE service_role';
END;
$$;

-- ============================================================================
-- 1. A logged-in user cannot insert evidence directly -- no grant exists.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.skill_evidence (user_id, skill_id, evidence_type, outcome, source_type, source_id)
    VALUES ('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'assessment', 'passed', 'exam', gen_random_uuid());
    RAISE EXCEPTION 'FAIL: authenticated user inserted skill_evidence directly';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: direct skill_evidence INSERT is rejected (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 2. A logged-in user cannot call record_skill_evidence() (no EXECUTE grant)
--    to fabricate mastery for themselves.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    PERFORM public.record_skill_evidence(
      '11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001',
      'assessment', 'passed', 'exam', gen_random_uuid()
    );
    RAISE EXCEPTION 'FAIL: authenticated user called record_skill_evidence() directly';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: record_skill_evidence() is not callable by authenticated (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 3. State machine, driven only via service_role (standing in for a grading
--    function running with the service key after independently verifying
--    the outcome).
-- ============================================================================
CALL test_act_as_service();

DO $$
DECLARE v_state public.skill_state;
BEGIN
  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: skill state exists before any evidence';
  END IF;
  RAISE NOTICE 'PASS: NOT_STARTED (no row) before any evidence';
END $$;

DO $$
DECLARE v_state public.skill_state;
BEGIN
  PERFORM public.record_skill_evidence('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'theory', 'passed', 'lesson', gen_random_uuid());
  SELECT state INTO v_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'LEARNING' THEN RAISE EXCEPTION 'FAIL: expected LEARNING, got %', v_state; END IF;
  RAISE NOTICE 'PASS: theory passed -> LEARNING';
END $$;

DO $$
DECLARE v_state public.skill_state;
BEGIN
  PERFORM public.record_skill_evidence('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'guided_lab', 'passed', 'lab', gen_random_uuid());
  SELECT state INTO v_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'PRACTICING' THEN RAISE EXCEPTION 'FAIL: expected PRACTICING, got %', v_state; END IF;
  RAISE NOTICE 'PASS: guided_lab passed -> PRACTICING';
END $$;

DO $$
DECLARE v_state public.skill_state;
BEGIN
  -- Assessment alone (no independent demonstration yet) -> ASSESSED, not MASTERED.
  PERFORM public.record_skill_evidence('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'assessment', 'passed', 'exam', gen_random_uuid());
  SELECT state INTO v_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'ASSESSED' THEN RAISE EXCEPTION 'FAIL: expected ASSESSED, got %', v_state; END IF;
  RAISE NOTICE 'PASS: assessment passed with no independent demo -> ASSESSED (not MASTERED)';
END $$;

DO $$
DECLARE v_state public.skill_state;
BEGIN
  PERFORM public.record_skill_evidence('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'unguided_lab', 'passed', 'lab', gen_random_uuid());
  SELECT state INTO v_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'DEMONSTRATED' THEN RAISE EXCEPTION 'FAIL: expected DEMONSTRATED, got %', v_state; END IF;
  RAISE NOTICE 'PASS: unguided_lab passed (assessment+demo, no retest yet) -> DEMONSTRATED';
END $$;

DO $$
DECLARE v_state public.skill_state;
BEGIN
  PERFORM public.record_skill_evidence('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'retest', 'passed', 'lab', gen_random_uuid());
  SELECT state INTO v_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'MASTERED' THEN RAISE EXCEPTION 'FAIL: expected MASTERED, got %', v_state; END IF;
  RAISE NOTICE 'PASS: assessment + independent demo + retest -> MASTERED';
END $$;

DO $$
DECLARE v_state public.skill_state;
BEGIN
  -- A later failed retest on an already-mastered skill must flag regression.
  PERFORM public.record_skill_evidence('11111111-1111-1111-1111-111111111111', '50000000-0000-0000-0000-000000000001', 'retest', 'failed', 'lab', gen_random_uuid());
  SELECT state INTO v_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = '50000000-0000-0000-0000-000000000001';
  IF v_state <> 'NEEDS_REVIEW' THEN RAISE EXCEPTION 'FAIL: expected NEEDS_REVIEW, got %', v_state; END IF;
  RAISE NOTICE 'PASS: failed retest after mastery -> NEEDS_REVIEW';
END $$;

-- ============================================================================
-- 4. Visibility: alice can read her own evidence/state; a stranger cannot.
-- ============================================================================
RESET ROLE; -- back to postgres superuser for fixture setup
INSERT INTO auth.users (id, email) VALUES ('22222222-2222-2222-2222-222222222222', 'bob@test.local');

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.skill_evidence WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 6 THEN RAISE EXCEPTION 'FAIL: alice should see her own 6 evidence rows, saw %', cnt; END IF;
  RAISE NOTICE 'PASS: user can read own evidence';
END $$;

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.skill_evidence WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob should not see alice''s evidence, saw %', cnt; END IF;
  SELECT count(*) INTO cnt FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob should not see alice''s skill state, saw %', cnt; END IF;
  RAISE NOTICE 'PASS: stranger cannot read another user''s evidence or skill state';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);
DROP PROCEDURE test_act_as_service();

ROLLBACK;

\echo 'ALL SKILL GRAPH TESTS PASSED'
