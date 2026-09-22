-- ============================================================================
-- Scanner AI-enrichment regression tests: enrich_scan_finding() can only be
-- called by the finding's owner (or staff), only ever changes descriptive
-- text (explanation/impact/remediation/secure_example) plus ai_enriched,
-- and never touches severity/category/verification_status/status -- so even
-- a compromised or misbehaving caller cannot use it to fabricate or
-- reclassify a finding.
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

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE
  v_scan_id uuid;
  v_file_id uuid;
BEGIN
  INSERT INTO public.scans (user_id, title, target_type, status)
  VALUES ('11111111-1111-1111-1111-111111111111', 'Test scan', 'pasted_snippet', 'running')
  RETURNING id INTO v_scan_id;

  INSERT INTO public.scan_files (scan_id, filename, content, size_bytes, content_sha256)
  VALUES (v_scan_id, 'app.js', 'eval(x);', octet_length('eval(x);'), encode(digest('eval(x);', 'sha256'), 'hex'))
  RETURNING id INTO v_file_id;

  INSERT INTO public.scan_findings (
    scan_id, file_id, rule_id, category, title, severity, confidence,
    line_start, line_end, evidence, explanation, impact, remediation, verification_status
  ) VALUES (
    v_scan_id, v_file_id, 'insecure-eval-eval', 'insecure_eval', 'eval() called with a dynamic argument',
    'critical', 'medium', 1, 1, 'eval(x);', 'baseline explanation', 'baseline impact', 'baseline remediation', 'needs_review'
  );
END $$;

-- ============================================================================
-- 1. Alice can enrich her own finding: only the descriptive text and
--    ai_enriched change; rule_id/category/severity/confidence/
--    verification_status/status are untouched.
-- ============================================================================
DO $$
DECLARE
  v_finding_id uuid;
  v_updated public.scan_findings;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;

  SELECT * INTO v_updated FROM public.enrich_scan_finding(
    v_finding_id,
    'A specific, evidence-grounded explanation.',
    'A specific impact statement.',
    'A specific remediation.',
    'const safe = () => 1;'
  );

  IF v_updated.explanation <> 'A specific, evidence-grounded explanation.' THEN
    RAISE EXCEPTION 'FAIL: explanation was not updated';
  END IF;
  IF v_updated.ai_enriched IS NOT true THEN
    RAISE EXCEPTION 'FAIL: ai_enriched was not set';
  END IF;
  IF v_updated.severity <> 'critical' OR v_updated.category <> 'insecure_eval' OR v_updated.rule_id <> 'insecure-eval-eval' THEN
    RAISE EXCEPTION 'FAIL: enrichment changed a fact-of-record field it must never touch';
  END IF;
  IF v_updated.verification_status <> 'needs_review' OR v_updated.status <> 'discovered' THEN
    RAISE EXCEPTION 'FAIL: enrichment changed verification_status or status';
  END IF;

  RAISE NOTICE 'PASS: enrichment updates only descriptive text, never fact-of-record fields';
END $$;

-- ============================================================================
-- 1b. count_my_scan_enrichments_today() reflects the caller's own count
--     without needing direct audit_log read access (which RLS reserves for
--     admins) -- this is what the enrichment rate limit reads.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT public.count_my_scan_enrichments_today() INTO v_count;
  IF v_count <> 1 THEN RAISE EXCEPTION 'FAIL: expected alice''s enrichment count to be 1, got %', v_count; END IF;
  RAISE NOTICE 'PASS: count_my_scan_enrichments_today() reflects the caller''s own enrichment calls';
END $$;

-- ============================================================================
-- 2. Bob cannot enrich Alice's finding.
-- ============================================================================
DO $$
DECLARE v_finding_id uuid;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;
  RESET ROLE;
  CALL test_act_as('22222222-2222-2222-2222-222222222222');

  BEGIN
    PERFORM public.enrich_scan_finding(v_finding_id, 'x', 'x', 'x', NULL);
    RAISE EXCEPTION 'FAIL: bob enriched alice''s finding';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot enrich another user''s finding (%)', SQLSTATE;
  END;
END $$;

DO $$
DECLARE v_count int;
BEGIN
  SELECT public.count_my_scan_enrichments_today() INTO v_count;
  IF v_count <> 0 THEN RAISE EXCEPTION 'FAIL: expected bob''s enrichment count to be 0, got %', v_count; END IF;
  RAISE NOTICE 'PASS: count_my_scan_enrichments_today() does not leak another user''s enrichment activity';
END $$;

-- ============================================================================
-- 3. Empty enrichment text is rejected (no silent no-op write).
-- ============================================================================
RESET ROLE;
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_finding_id uuid;
BEGIN
  SELECT id INTO v_finding_id FROM public.scan_findings LIMIT 1;
  BEGIN
    PERFORM public.enrich_scan_finding(v_finding_id, '   ', 'impact', 'remediation', NULL);
    RAISE EXCEPTION 'FAIL: empty explanation was accepted';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: empty enrichment text is rejected (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 4. Every enrichment call is audit-logged (admin-only readable).
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.audit_log WHERE action = 'scan_finding.ai_enriched';
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 audit_log entry, got %', cnt; END IF;
  RAISE NOTICE 'PASS: enrichment is audit-logged';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL SCANNER ENRICHMENT RLS TESTS PASSED'
