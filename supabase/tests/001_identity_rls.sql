-- ============================================================================
-- RLS regression tests: identity, RBAC, organizations, audit log.
--
-- Runs as the postgres superuser but switches to the anon/authenticated
-- Postgres role (and sets the request.jwt.claims GUC that auth.uid()/
-- auth.role() read, exactly as PostgREST does for a real request) before
-- each assertion, so policies are genuinely exercised rather than bypassed.
--
-- Failure mode: any RAISE EXCEPTION aborts the script with a non-zero exit
-- code from psql (ON_ERROR_STOP=1), which is what fails CI.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---- Fixtures --------------------------------------------------------------
INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local');

-- handle_new_user() trigger already created profiles + 'user' roles for all three.
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '33333333-3333-3333-3333-333333333333';
INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-3333-3333-333333333333', 'admin')
  ON CONFLICT DO NOTHING;

-- Helper: switch to `authenticated` acting as the given user id.
CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE format('SET ROLE authenticated');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CREATE OR REPLACE PROCEDURE test_act_as_anon() LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE format('SET ROLE anon');
  PERFORM set_config('request.jwt.claims', '', false);
END;
$$;

CREATE OR REPLACE PROCEDURE test_reset() LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', false);
END;
$$;

-- ============================================================================
-- 1. Anonymous users cannot read profiles (auth wall).
-- ============================================================================
CALL test_act_as_anon();
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.profiles;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon should not see any profiles, saw %', cnt;
  END IF;
  RAISE NOTICE 'PASS: anon cannot read profiles';
END $$;

-- ============================================================================
-- 2. Authenticated users can read all profiles, but only update their own.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.profiles;
  IF cnt <> 3 THEN
    RAISE EXCEPTION 'FAIL: authenticated user should see all 3 profiles, saw %', cnt;
  END IF;
  RAISE NOTICE 'PASS: authenticated user can read all profiles';
END $$;

DO $$
DECLARE affected int;
BEGIN
  UPDATE public.profiles SET bio = 'hacked' WHERE id = '22222222-2222-2222-2222-222222222222';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN
    RAISE EXCEPTION 'FAIL: alice updated bob''s profile (% rows)', affected;
  END IF;
  RAISE NOTICE 'PASS: user cannot update another user''s profile';
END $$;

DO $$
DECLARE affected int;
BEGIN
  UPDATE public.profiles SET bio = 'my own bio' WHERE id = '11111111-1111-1111-1111-111111111111';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 THEN
    RAISE EXCEPTION 'FAIL: alice could not update her own profile (% rows)', affected;
  END IF;
  RAISE NOTICE 'PASS: user can update own profile';
END $$;

-- ============================================================================
-- 3. PRIVILEGE ESCALATION: a normal user must never be able to grant
--    themselves (or anyone) an elevated role. This is the single most
--    important test in this file.
-- ============================================================================
DO $$
BEGIN
  BEGIN
    INSERT INTO public.user_roles (user_id, role) VALUES ('11111111-1111-1111-1111-111111111111', 'admin');
    RAISE EXCEPTION 'FAIL: alice was able to insert an admin role for herself';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN
        RAISE; -- re-raise our own FAIL exception
      END IF;
      RAISE NOTICE 'PASS: self-granting admin role was rejected (%)', SQLSTATE;
  END;
END $$;

DO $$
DECLARE affected int;
BEGIN
  -- Even trying to *escalate an existing row* must fail: alice has no row to
  -- update to 'admin' since she only has 'user', but prove UPDATE is denied
  -- outright for non-admins regardless of target row.
  UPDATE public.user_roles SET role = 'admin' WHERE user_id = '11111111-1111-1111-1111-111111111111' AND role = 'user';
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN
    RAISE EXCEPTION 'FAIL: alice escalated her own role via UPDATE (% rows)', affected;
  END IF;
  RAISE NOTICE 'PASS: user cannot escalate own role via UPDATE';
END $$;

-- A user CAN see their own role assignments (read-only visibility).
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.user_roles WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: alice should see her own 1 role row, saw %', cnt;
  END IF;
  RAISE NOTICE 'PASS: user can read own role assignments';
END $$;

-- A user CANNOT see another user's role assignments.
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.user_roles WHERE user_id = '33333333-3333-3333-3333-333333333333';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: alice should not see admin''s role rows, saw %', cnt;
  END IF;
  RAISE NOTICE 'PASS: user cannot read another user''s role assignments';
END $$;

-- ============================================================================
-- 4. Admin CAN grant roles.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE affected int;
BEGIN
  INSERT INTO public.user_roles (user_id, role, granted_by)
  VALUES ('22222222-2222-2222-2222-222222222222', 'instructor', '33333333-3333-3333-3333-333333333333');
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 1 THEN
    RAISE EXCEPTION 'FAIL: admin could not grant instructor role (% rows)', affected;
  END IF;
  RAISE NOTICE 'PASS: admin can grant roles';
END $$;

-- ============================================================================
-- 5. Audit log: direct INSERT by a non-service role must fail outright
--    (no GRANT exists); log_audit_event() must succeed and be attributed to
--    the caller; only admins may read it.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.audit_log (actor_id, action) VALUES ('11111111-1111-1111-1111-111111111111', 'forged.event');
    RAISE EXCEPTION 'FAIL: direct INSERT into audit_log succeeded for a non-service role';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: direct INSERT into audit_log is rejected (%)', SQLSTATE;
  END;
END $$;

DO $$
DECLARE v_id bigint;
DECLARE cnt int;
BEGIN
  SELECT public.log_audit_event('lab.started', 'lab', 'sqli-101') INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: log_audit_event did not return an id';
  END IF;
  -- alice cannot read the audit log even though she caused this entry.
  SELECT count(*) INTO cnt FROM public.audit_log WHERE id = v_id;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: non-admin could read audit_log entry';
  END IF;
  RAISE NOTICE 'PASS: log_audit_event() works and is not readable by non-admins';
END $$;

CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.audit_log WHERE action = 'lab.started';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: admin should see the logged event, saw %', cnt;
  END IF;
  RAISE NOTICE 'PASS: admin can read audit_log';
END $$;

DO $$
DECLARE affected int;
BEGIN
  BEGIN
    UPDATE public.audit_log SET action = 'tampered' WHERE action = 'lab.started';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN
      RAISE EXCEPTION 'FAIL: audit_log entry was mutated (% rows)', affected;
    END IF;
  EXCEPTION
    WHEN insufficient_privilege THEN NULL; -- also acceptable: outright denied
  END;
  RAISE NOTICE 'PASS: audit_log is immutable, even for admins';
END $$;

-- ============================================================================
-- 6. Organizations: creator becomes team_owner; a plain member cannot alter
--    org membership or add themselves as org_admin.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  INSERT INTO public.organizations (id, slug, name, created_by)
  VALUES ('44444444-4444-4444-4444-444444444444', 'acme-security', 'Acme Security', '11111111-1111-1111-1111-111111111111');
END $$;

DO $$
DECLARE r public.org_role;
BEGIN
  SELECT role INTO r FROM public.organization_members
    WHERE organization_id = '44444444-4444-4444-4444-444444444444'
      AND user_id = '11111111-1111-1111-1111-111111111111';
  IF r IS DISTINCT FROM 'team_owner' THEN
    RAISE EXCEPTION 'FAIL: org creator should be team_owner, got %', r;
  END IF;
  RAISE NOTICE 'PASS: org creator auto-assigned team_owner';
END $$;

CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE affected int;
BEGIN
  -- bob is not a member of acme-security at all; he must not be able to add himself.
  BEGIN
    INSERT INTO public.organization_members (organization_id, user_id, role)
    VALUES ('44444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'org_admin');
    RAISE EXCEPTION 'FAIL: bob added himself as org_admin of a foreign org';
  EXCEPTION
    WHEN others THEN
      IF SQLSTATE = 'P0001' THEN RAISE; END IF;
      RAISE NOTICE 'PASS: outsider cannot self-add to an organization (%)', SQLSTATE;
  END;
END $$;

DO $$
DECLARE cnt int;
BEGIN
  -- bob also should not even be able to SEE the org he isn't a member of.
  SELECT count(*) INTO cnt FROM public.organizations WHERE id = '44444444-4444-4444-4444-444444444444';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: bob can see an organization he is not a member of';
  END IF;
  RAISE NOTICE 'PASS: non-member cannot see organization';
END $$;

CALL test_reset();
DROP PROCEDURE test_act_as(uuid);
DROP PROCEDURE test_act_as_anon();
DROP PROCEDURE test_reset();

ROLLBACK;

\echo 'ALL IDENTITY/RBAC RLS TESTS PASSED'
