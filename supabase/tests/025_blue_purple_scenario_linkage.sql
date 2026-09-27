-- ============================================================================
-- Proves Blue/Purple Team scenario linkage (20260922000028) is real:
-- anyone can read an investigation<->lab/CTF link, only staff can write one,
-- and the seeded Purple Team pairing (20260922000029) actually links the
-- new investigation to the real Cyber Range lab it's the blue-team side of.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice-staff@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob-plain@test.local');

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin');

INSERT INTO public.investigations (id, slug, title, category, difficulty, published)
VALUES ('d0000000-0000-0000-0000-000000000001', 'test-linkage-investigation', 'Test Linkage Investigation', 'forensics', 'easy', true);
INSERT INTO public.labs (id, slug, title, category, difficulty, published)
VALUES ('d0000000-0000-0000-0000-000000000002', 'test-linkage-lab', 'Test Linkage Lab', 'linux', 'easy', true);
INSERT INTO public.ctf_challenges (id, slug, title, category, difficulty, points, flag_hash, published)
VALUES ('d0000000-0000-0000-0000-000000000003', 'test-linkage-ctf', 'Test Linkage CTF', 'linux', 'easy', 100, encode(digest('x', 'sha256'), 'hex'), true);

-- ============================================================================
-- 1. Staff can link an investigation to a lab and to a CTF challenge.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
INSERT INTO public.investigation_labs (investigation_id, lab_id)
VALUES ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002');
INSERT INTO public.investigation_ctf_challenges (investigation_id, challenge_id)
VALUES ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000003');
\echo 'PASS: staff linked an investigation to a lab and a CTF challenge'

-- ============================================================================
-- 2. A plain user cannot create a link.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.investigation_labs (investigation_id, lab_id)
    VALUES ('d0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'FAIL: a plain user created an investigation_labs link';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: a plain user cannot create an investigation_labs link (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 3. A plain user CAN read the link (it's not sensitive -- same as
--    capstone_labs/capstone_skills).
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.investigation_labs
    WHERE investigation_id = 'd0000000-0000-0000-0000-000000000001';
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected a plain user to read the investigation_labs link, got %', v_count; END IF;
  RAISE NOTICE 'PASS: a plain user can read an investigation_labs link';
END $$;

-- ============================================================================
-- 4. Deleting the lab cascades the link (it's a plain junction row, no
--    attribution semantics to preserve).
-- ============================================================================
RESET ROLE;
DO $$
DECLARE v_count int;
BEGIN
  DELETE FROM public.labs WHERE id = 'd0000000-0000-0000-0000-000000000002';
  SELECT count(*) INTO v_count FROM public.investigation_labs WHERE investigation_id = 'd0000000-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: expected the investigation_labs link to be gone after the lab was deleted'; END IF;
  RAISE NOTICE 'PASS: deleting the lab cascades its investigation_labs link';
END $$;

-- ============================================================================
-- 5. The real seeded Purple Team pairing exists: the seeded investigation
--    genuinely links to the seeded Cyber Range lab it's the blue-team side
--    of (not two disconnected pieces of content).
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.investigation_labs il
  JOIN public.investigations i ON i.id = il.investigation_id
  JOIN public.labs l ON l.id = il.lab_id
  WHERE i.slug = 'purple-team-db-lateral-movement' AND l.slug = 'cyber-range-lateral-movement-db';
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected the seeded Purple Team pairing to link the two real seeded rows, got %', v_count; END IF;
  RAISE NOTICE 'PASS: the seeded Purple Team investigation genuinely links to the seeded Cyber Range lab';
END $$;

DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL BLUE/PURPLE SCENARIO LINKAGE TESTS PASSED'
