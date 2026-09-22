-- ============================================================================
-- Security scanner RLS + lifecycle regression tests: a user's scans/files/
-- findings are private to them (plus staff), findings can only be created
-- for a scan the caller owns, and a finding's status can only change through
-- transition_scan_finding_status() following the attack -> fix -> retest
-- state graph -- never by direct UPDATE, and never by a non-owner.
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

-- ============================================================================
-- 1. Alice can create a scan, a file, and a finding for it; the summary
--    triggers keep scans.total_files/total_findings/findings_by_severity
--    accurate without the client asserting them.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE
  v_scan_id uuid;
  v_file_id uuid;
  v_finding_id uuid;
  v_total_files int;
  v_total_findings int;
  v_by_severity jsonb;
BEGIN
  INSERT INTO public.scans (user_id, title, target_type, status)
  VALUES ('11111111-1111-1111-1111-111111111111', 'Test scan', 'pasted_snippet', 'running')
  RETURNING id INTO v_scan_id;

  INSERT INTO public.scan_files (scan_id, filename, language, content, size_bytes, content_sha256)
  VALUES (
    v_scan_id, 'app.js', 'javascript',
    'const query = "SELECT * FROM users WHERE id = " + req.query.id;',
    octet_length('const query = "SELECT * FROM users WHERE id = " + req.query.id;'),
    encode(digest('const query = "SELECT * FROM users WHERE id = " + req.query.id;', 'sha256'), 'hex')
  )
  RETURNING id INTO v_file_id;

  INSERT INTO public.scan_findings (
    scan_id, file_id, rule_id, category, title, severity, confidence,
    line_start, line_end, evidence, explanation, impact, remediation,
    verification_status
  ) VALUES (
    v_scan_id, v_file_id, 'sql-injection-string-concat', 'sql_injection',
    'SQL query built via string concatenation', 'high', 'high',
    1, 1, 'const query = "SELECT * FROM users WHERE id = " + req.query.id;',
    'User input is concatenated directly into a SQL query string.',
    'An attacker can alter query logic or exfiltrate data.',
    'Use a parameterized query / prepared statement instead of string concatenation.',
    'true_positive'
  ) RETURNING id INTO v_finding_id;

  SELECT total_files, total_findings, findings_by_severity
  INTO v_total_files, v_total_findings, v_by_severity
  FROM public.scans WHERE id = v_scan_id;

  IF v_total_files <> 1 THEN RAISE EXCEPTION 'FAIL: expected total_files=1, got %', v_total_files; END IF;
  IF v_total_findings <> 1 THEN RAISE EXCEPTION 'FAIL: expected total_findings=1, got %', v_total_findings; END IF;
  IF (v_by_severity->>'high')::int <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected findings_by_severity.high=1, got %', v_by_severity;
  END IF;

  RAISE NOTICE 'PASS: alice can create a scan/file/finding; summary counts auto-computed';
END $$;

-- ============================================================================
-- 2. Bob cannot see Alice's scan, files, or findings.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.scans WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s scans'; END IF;

  SELECT count(*) INTO cnt FROM public.scan_files;
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s scan files'; END IF;

  SELECT count(*) INTO cnt FROM public.scan_findings;
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s scan findings'; END IF;

  RAISE NOTICE 'PASS: another user cannot read alice''s scans/files/findings';
END $$;

-- ============================================================================
-- 3. Bob cannot insert a file or finding into Alice's scan, even though he
--    supplies a real scan_id (ownership is checked via the parent scan, not
--    just accepted from the client).
-- ============================================================================
DO $$
DECLARE v_alice_scan_id uuid;
BEGIN
  RESET ROLE;
  SELECT id INTO v_alice_scan_id FROM public.scans WHERE user_id = '11111111-1111-1111-1111-111111111111' LIMIT 1;
  CALL test_act_as('22222222-2222-2222-2222-222222222222');

  BEGIN
    INSERT INTO public.scan_files (scan_id, filename, content, size_bytes, content_sha256)
    VALUES (v_alice_scan_id, 'evil.js', 'x', 1, encode(digest('x', 'sha256'), 'hex'));
    RAISE EXCEPTION 'FAIL: bob inserted a file into alice''s scan';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot insert a file into another user''s scan (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 4. Staff can read any scan/file/finding for support/review.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.scans WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: admin should see alice''s scan, saw %', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.scan_findings;
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: admin should see alice''s finding, saw %', cnt; END IF;

  RAISE NOTICE 'PASS: staff can read any scan/file/finding';
END $$;

-- ============================================================================
-- 5. Nobody can directly UPDATE a finding's status -- there is no UPDATE
--    policy on scan_findings for `authenticated`; only
--    transition_scan_finding_status() (SECURITY DEFINER) can change it.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE affected int;
BEGIN
  BEGIN
    UPDATE public.scan_findings SET status = 'verified_fixed'
    WHERE scan_id IN (SELECT id FROM public.scans WHERE user_id = '11111111-1111-1111-1111-111111111111');
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN RAISE EXCEPTION 'FAIL: direct UPDATE changed % finding row(s)', affected; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS: scan_findings.status cannot be changed by a direct UPDATE';
END $$;

-- ============================================================================
-- 6. transition_scan_finding_status(): illegal transitions are rejected
--    (discovered -> verified_fixed skips the required fix/retest steps).
-- ============================================================================
DO $$
DECLARE v_finding_id uuid;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;
  BEGIN
    PERFORM public.transition_scan_finding_status(v_finding_id, 'verified_fixed', 'skip ahead');
    RAISE EXCEPTION 'FAIL: illegal transition discovered -> verified_fixed was allowed';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: illegal status transition rejected (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 7. Bob cannot transition a finding on Alice's scan.
-- ============================================================================
DO $$
DECLARE v_finding_id uuid;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;
  RESET ROLE;
  CALL test_act_as('22222222-2222-2222-2222-222222222222');
  BEGIN
    PERFORM public.transition_scan_finding_status(v_finding_id, 'remediation_required', NULL);
    RAISE EXCEPTION 'FAIL: bob transitioned alice''s finding status';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot transition another user''s finding (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 8. Alice walks the legal attack -> fix -> retest path; each step writes a
--    history row (scan_finding_status_events) and an audit_log entry.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE
  v_finding_id uuid;
  v_status public.scan_finding_status;
  v_history_count int;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;

  PERFORM public.transition_scan_finding_status(v_finding_id, 'remediation_required', 'triaged: real SQLi');
  PERFORM public.transition_scan_finding_status(v_finding_id, 'fix_applied', 'switched to parameterized query');
  PERFORM public.transition_scan_finding_status(v_finding_id, 'retested', 'rescanned the fixed file');
  PERFORM public.transition_scan_finding_status(v_finding_id, 'verified_fixed', 'rescan found no SQLi in this file');

  SELECT status INTO v_status FROM public.scan_findings WHERE id = v_finding_id;
  IF v_status <> 'verified_fixed' THEN
    RAISE EXCEPTION 'FAIL: expected final status verified_fixed, got %', v_status;
  END IF;

  SELECT count(*) INTO v_history_count FROM public.scan_finding_status_events WHERE finding_id = v_finding_id;
  IF v_history_count <> 4 THEN
    RAISE EXCEPTION 'FAIL: expected 4 history events, got %', v_history_count;
  END IF;

  RAISE NOTICE 'PASS: full attack -> fix -> retest path succeeds and is recorded';
END $$;

-- Idempotent: transitioning to the current status again is a no-op, not an
-- error, and does not add a spurious history row.
DO $$
DECLARE v_finding_id uuid; v_history_count_before int; v_history_count_after int;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;
  SELECT count(*) INTO v_history_count_before FROM public.scan_finding_status_events WHERE finding_id = v_finding_id;

  PERFORM public.transition_scan_finding_status(v_finding_id, 'verified_fixed', NULL);

  SELECT count(*) INTO v_history_count_after FROM public.scan_finding_status_events WHERE finding_id = v_finding_id;
  IF v_history_count_after <> v_history_count_before THEN
    RAISE EXCEPTION 'FAIL: re-asserting the same status added a history row';
  END IF;
  RAISE NOTICE 'PASS: re-asserting the current status is a no-op';
END $$;

-- ============================================================================
-- 9. Audit log recorded the status changes (admin-only readable).
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.audit_log WHERE action = 'scan_finding.status_changed';
  IF cnt <> 4 THEN RAISE EXCEPTION 'FAIL: expected 4 audit_log entries, got %', cnt; END IF;
  RAISE NOTICE 'PASS: every status transition is audit-logged';
END $$;

-- ============================================================================
-- 10. Only a staff member (not the plain finding owner beyond their own) can
--     read the status history of a finding they don't own; a non-owner gets
--     zero rows.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.scan_finding_status_events;
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s finding status history'; END IF;
  RAISE NOTICE 'PASS: finding status history is private to the owner (and staff)';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL SECURITY SCANNER RLS TESTS PASSED'
