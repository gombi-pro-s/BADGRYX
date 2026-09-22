-- ============================================================================
-- AI-assisted enrichment for scan findings (section 8/11): lets a later
-- Anthropic call improve a finding's explanation/impact/remediation text,
-- without ever gaining the ability to invent a finding, change its
-- severity/category, or touch its verification_status or attack -> fix ->
-- retest status. See docs/adr/0008-scanner-finding-lifecycle.md.
--
-- This is the same non-fabrication principle as the AI Mentor (ADR 0007),
-- applied here structurally rather than just by prompt instruction:
-- enrich_scan_finding()'s parameter list has no slot for severity/category/
-- verification_status/status at all, so there is no write path from "the
-- model said so" to changing any of those, no matter what the model
-- outputs.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enrich_scan_finding(
  p_finding_id uuid,
  p_explanation text,
  p_impact text,
  p_remediation text,
  p_secure_example text DEFAULT NULL
)
  RETURNS public.scan_findings
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_finding public.scan_findings;
  v_owner_id uuid;
BEGIN
  SELECT f.* INTO v_finding
  FROM public.scan_findings f
  WHERE f.id = p_finding_id
  FOR UPDATE OF f;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Finding not found.' USING ERRCODE = 'P0002';
  END IF;

  SELECT s.user_id INTO v_owner_id FROM public.scans s WHERE s.id = v_finding.scan_id;

  IF v_owner_id <> auth.uid() AND NOT public.is_staff() THEN
    RAISE EXCEPTION 'Not authorized to enrich this finding.' USING ERRCODE = 'P0005';
  END IF;

  IF length(trim(p_explanation)) = 0 OR length(trim(p_impact)) = 0 OR length(trim(p_remediation)) = 0 THEN
    RAISE EXCEPTION 'Enrichment text cannot be empty.' USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.scan_findings
  SET
    explanation = p_explanation,
    impact = p_impact,
    remediation = p_remediation,
    secure_example = COALESCE(p_secure_example, secure_example),
    ai_enriched = true
  WHERE id = p_finding_id
  RETURNING * INTO v_finding;

  PERFORM public.log_audit_event(
    'scan_finding.ai_enriched',
    'scan_finding',
    p_finding_id::text,
    NULL,
    jsonb_build_object('scan_id', v_finding.scan_id)
  );

  RETURN v_finding;
END;
$$;

REVOKE ALL ON FUNCTION public.enrich_scan_finding(uuid, text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.enrich_scan_finding(uuid, text, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.enrich_scan_finding IS
  'The only way scan_findings.explanation/impact/remediation/secure_example '
  'can change after insert. Deliberately has no parameter for severity, '
  'category, verification_status, or status -- an AI-enrichment caller '
  'structurally cannot use this function to fabricate or reclassify a '
  'finding, only to improve its descriptive text.';

-- ----------------------------------------------------------------------------
-- Rate-limit AI enrichment through the real entitlement engine, same as
-- every other AI-backed feature (ai_mentor_daily_requests,
-- scanner_daily_scans). enrich_scan_finding() itself has no per-call cost
-- control -- that lives at the API route, which needs to count *this specific
-- user's* enrichment calls today. audit_log (where every enrichment call is
-- recorded) is admin-only readable by RLS, so a small SECURITY DEFINER
-- helper -- scoped internally to auth.uid(), never a caller-supplied id --
-- is what lets a user's own session read their own count without opening
-- audit_log itself up more broadly.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.count_my_scan_enrichments_today()
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  STABLE
  SET search_path = public, pg_temp
AS $$
  SELECT count(*)::integer
  FROM public.audit_log
  WHERE actor_id = auth.uid()
    AND action = 'scan_finding.ai_enriched'
    AND created_at >= date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
$$;

REVOKE ALL ON FUNCTION public.count_my_scan_enrichments_today() FROM public;
GRANT EXECUTE ON FUNCTION public.count_my_scan_enrichments_today() TO authenticated;

COMMENT ON FUNCTION public.count_my_scan_enrichments_today IS
  'Lets a user''s own session read their own today-count of '
  'scan_finding.ai_enriched audit_log entries, for the enrichment rate '
  'limit, without granting broader read access to audit_log.';

INSERT INTO public.plan_entitlements (plan_id, key, value)
SELECT id, 'scanner_daily_enrichments', '20'::jsonb FROM public.plans WHERE slug = 'free';
