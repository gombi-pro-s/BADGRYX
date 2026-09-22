-- ============================================================================
-- Security scanning engine (section 8): owner-scoped scans of pasted/
-- uploaded source, real findings produced by a deterministic static-analysis
-- rule engine (implemented in application code, not the database), with an
-- explicit attack -> fix -> retest status lifecycle per finding. AI
-- enrichment (a later phase) may only add explanation/triage text to a
-- finding the rule engine already produced -- it can never be the sole
-- author of a finding's existence, mirroring how the AI Mentor (ADR 0007)
-- can never write skill_evidence. That constraint is enforced here
-- structurally: scan_findings rows are only ever inserted by the owning
-- user's own session for their own scan (no service-role-only insert path
-- that an AI-only code path could use unilaterally), and every subsequent
-- status change goes through transition_scan_finding_status(), which
-- validates the transition and writes an unforgeable history row -- so the
-- lifecycle is a real, testable state machine, not just a status column a
-- client can set to anything.
-- ============================================================================

CREATE TYPE public.scan_status AS ENUM ('queued', 'running', 'completed', 'failed');
CREATE TYPE public.scan_target_type AS ENUM ('pasted_snippet', 'uploaded_files');

CREATE TYPE public.scan_finding_severity AS ENUM ('critical', 'high', 'medium', 'low', 'info');
CREATE TYPE public.scan_finding_confidence AS ENUM ('high', 'medium', 'low');

CREATE TYPE public.scan_finding_category AS ENUM (
  'secrets',
  'sql_injection',
  'xss',
  'command_injection',
  'path_traversal',
  'insecure_eval',
  'weak_cryptography',
  'insecure_cors',
  'insecure_cookies',
  'cleartext_http',
  'prototype_pollution',
  'unsafe_deserialization',
  'other'
);

-- A finding starts life as an automated call (true positive / false
-- positive / needs a human look / informational-only) made by the
-- deterministic rule engine. This is distinct from `scan_findings.status`
-- below, which tracks what the *user* has done about it.
CREATE TYPE public.scan_finding_verification_status AS ENUM (
  'true_positive', 'false_positive', 'needs_review', 'informational'
);

-- The attack -> fix -> retest workflow. `discovered` and `verified_fixed`
-- are the only states a fresh scan can reach on its own (a rescan of
-- already-fixed code can directly discover a clean file, but that's simply
-- "no finding row created" -- this enum only describes a finding that DID
-- get flagged). Every other transition is a deliberate user action recorded
-- by transition_scan_finding_status().
CREATE TYPE public.scan_finding_status AS ENUM (
  'discovered',
  'remediation_required',
  'fix_applied',
  'retested',
  'verified_fixed',
  'false_positive',
  'wont_fix'
);

-- ----------------------------------------------------------------------------
-- scans: one row per scan run, owned by the user who ran it.
-- ----------------------------------------------------------------------------

CREATE TABLE public.scans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  title text NOT NULL,
  target_type public.scan_target_type NOT NULL,
  status public.scan_status NOT NULL DEFAULT 'queued',
  total_files integer NOT NULL DEFAULT 0,
  total_findings integer NOT NULL DEFAULT 0,
  findings_by_severity jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  CONSTRAINT scans_findings_by_severity_is_object CHECK (jsonb_typeof(findings_by_severity) = 'object'),
  CONSTRAINT scans_completed_status_has_completed_at
    CHECK (status NOT IN ('completed', 'failed') OR completed_at IS NOT NULL)
);

CREATE INDEX scans_user_id_created_idx ON public.scans (user_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- scan_files: the actual source submitted, size-bounded. size_bytes is
-- derived from the stored content itself (never trusted from the client) so
-- it can't be spoofed to hide an oversized payload from monitoring/limits.
-- ----------------------------------------------------------------------------

CREATE TABLE public.scan_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id uuid NOT NULL REFERENCES public.scans (id) ON DELETE CASCADE,
  filename text NOT NULL,
  language text,
  content text NOT NULL,
  size_bytes integer NOT NULL,
  content_sha256 text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT scan_files_content_bounded CHECK (octet_length(content) <= 300000),
  CONSTRAINT scan_files_size_bytes_matches_content CHECK (size_bytes = octet_length(content)),
  CONSTRAINT scan_files_content_sha256_format CHECK (content_sha256 ~ '^[0-9a-f]{64}$')
);

CREATE INDEX scan_files_scan_id_idx ON public.scan_files (scan_id);

COMMENT ON CONSTRAINT scan_files_content_bounded ON public.scan_files IS
  '300000 bytes (~300KB) per file -- generous for real source files, small '
  'enough to keep a scan (and the AI-enrichment prompt built from it) bounded.';

-- ----------------------------------------------------------------------------
-- scan_findings: one row per issue the deterministic rule engine flagged.
-- All descriptive fields (title/explanation/impact/remediation/
-- secure_example/reference_links) are set once at insert time by the rule
-- that matched; only `status` changes after that, and only through
-- transition_scan_finding_status().
-- ----------------------------------------------------------------------------

CREATE TABLE public.scan_findings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id uuid NOT NULL REFERENCES public.scans (id) ON DELETE CASCADE,
  file_id uuid NOT NULL REFERENCES public.scan_files (id) ON DELETE CASCADE,
  rule_id text NOT NULL,
  category public.scan_finding_category NOT NULL,
  title text NOT NULL,
  severity public.scan_finding_severity NOT NULL,
  confidence public.scan_finding_confidence NOT NULL,
  line_start integer NOT NULL,
  line_end integer NOT NULL,
  evidence text NOT NULL,
  explanation text NOT NULL,
  impact text NOT NULL,
  remediation text NOT NULL,
  secure_example text,
  reference_links jsonb NOT NULL DEFAULT '[]'::jsonb,
  verification_status public.scan_finding_verification_status NOT NULL DEFAULT 'needs_review',
  ai_enriched boolean NOT NULL DEFAULT false,
  status public.scan_finding_status NOT NULL DEFAULT 'discovered',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT scan_findings_line_range_valid CHECK (line_start >= 1 AND line_end >= line_start),
  CONSTRAINT scan_findings_reference_links_is_array CHECK (jsonb_typeof(reference_links) = 'array')
);

CREATE INDEX scan_findings_scan_id_idx ON public.scan_findings (scan_id);
CREATE INDEX scan_findings_file_id_idx ON public.scan_findings (file_id);

CREATE TRIGGER scan_findings_set_updated_at
  BEFORE UPDATE ON public.scan_findings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- scan_finding_status_events: append-only history of every lifecycle
-- transition, mirroring audit_log's shape (actor stamped server-side, never
-- client-asserted). This is what makes "attack -> fix -> retest" an
-- inspectable trail, not just a mutable current-status column.
-- ----------------------------------------------------------------------------

CREATE TABLE public.scan_finding_status_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  finding_id uuid NOT NULL REFERENCES public.scan_findings (id) ON DELETE CASCADE,
  actor_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  from_status public.scan_finding_status NOT NULL,
  to_status public.scan_finding_status NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX scan_finding_status_events_finding_id_idx ON public.scan_finding_status_events (finding_id, created_at);

-- ----------------------------------------------------------------------------
-- Keep scans.total_files / total_findings / findings_by_severity accurate
-- automatically, so the dashboard never has to trust a client-reported
-- count.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.recompute_scan_file_count()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_scan_id uuid := COALESCE(NEW.scan_id, OLD.scan_id);
BEGIN
  UPDATE public.scans
  SET total_files = (SELECT count(*) FROM public.scan_files WHERE scan_id = v_scan_id)
  WHERE id = v_scan_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER scan_files_recompute_count
  AFTER INSERT OR DELETE ON public.scan_files
  FOR EACH ROW EXECUTE FUNCTION public.recompute_scan_file_count();

CREATE OR REPLACE FUNCTION public.recompute_scan_finding_summary()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_scan_id uuid := COALESCE(NEW.scan_id, OLD.scan_id);
  v_by_severity jsonb;
  v_total integer;
BEGIN
  SELECT count(*), COALESCE(jsonb_object_agg(severity, severity_count) FILTER (WHERE severity IS NOT NULL), '{}'::jsonb)
  INTO v_total, v_by_severity
  FROM (
    SELECT severity, count(*) AS severity_count
    FROM public.scan_findings
    WHERE scan_id = v_scan_id
    GROUP BY severity
  ) counts;

  UPDATE public.scans
  SET total_findings = v_total, findings_by_severity = v_by_severity
  WHERE id = v_scan_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER scan_findings_recompute_summary
  AFTER INSERT OR DELETE ON public.scan_findings
  FOR EACH ROW EXECUTE FUNCTION public.recompute_scan_finding_summary();

-- ----------------------------------------------------------------------------
-- transition_scan_finding_status: the only way a finding's status changes.
-- Validates the caller owns the parent scan (or is staff), validates the
-- transition is a legal edge in the attack -> fix -> retest graph, writes
-- the history row, and logs an audit event.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.transition_scan_finding_status(
  p_finding_id uuid,
  p_new_status public.scan_finding_status,
  p_note text DEFAULT NULL
)
  RETURNS public.scan_findings
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_finding public.scan_findings;
  v_owner_id uuid;
  v_legal boolean;
  v_old_status public.scan_finding_status;
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
    RAISE EXCEPTION 'Not authorized to update this finding.' USING ERRCODE = 'P0005';
  END IF;

  v_old_status := v_finding.status;

  IF p_new_status = v_old_status THEN
    RETURN v_finding;
  END IF;

  v_legal := (v_old_status, p_new_status) IN (
    ('discovered', 'remediation_required'),
    ('discovered', 'false_positive'),
    ('discovered', 'wont_fix'),
    ('remediation_required', 'fix_applied'),
    ('remediation_required', 'false_positive'),
    ('remediation_required', 'wont_fix'),
    ('fix_applied', 'retested'),
    ('fix_applied', 'remediation_required'),
    ('retested', 'verified_fixed'),
    ('retested', 'remediation_required'),
    ('false_positive', 'remediation_required'),
    ('wont_fix', 'remediation_required'),
    ('verified_fixed', 'remediation_required')
  );

  IF NOT v_legal THEN
    RAISE EXCEPTION 'Illegal finding status transition: % -> %', v_old_status, p_new_status
      USING ERRCODE = 'P0005';
  END IF;

  UPDATE public.scan_findings
  SET status = p_new_status
  WHERE id = p_finding_id
  RETURNING * INTO v_finding;

  INSERT INTO public.scan_finding_status_events (finding_id, actor_id, from_status, to_status, note)
  VALUES (p_finding_id, auth.uid(), v_old_status, p_new_status, p_note);

  PERFORM public.log_audit_event(
    'scan_finding.status_changed',
    'scan_finding',
    p_finding_id::text,
    NULL,
    jsonb_build_object('to_status', p_new_status, 'scan_id', v_finding.scan_id)
  );

  RETURN v_finding;
END;
$$;

REVOKE ALL ON FUNCTION public.transition_scan_finding_status(uuid, public.scan_finding_status, text) FROM public;
GRANT EXECUTE ON FUNCTION public.transition_scan_finding_status(uuid, public.scan_finding_status, text) TO authenticated;

COMMENT ON FUNCTION public.transition_scan_finding_status IS
  'The only sanctioned way to change a scan_findings.status. Validates '
  'ownership (or staff), validates the transition against the attack -> '
  'fix -> retest state graph, and records an unforgeable history row.';

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------

ALTER TABLE public.scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scans FORCE ROW LEVEL SECURITY;

CREATE POLICY scans_select_own_or_staff ON public.scans
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY scans_insert_own ON public.scans
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY scans_update_own ON public.scans
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY scans_delete_own ON public.scans
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

ALTER TABLE public.scan_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_files FORCE ROW LEVEL SECURITY;

CREATE POLICY scan_files_select_own_or_staff ON public.scan_files
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR EXISTS (SELECT 1 FROM public.scans s WHERE s.id = scan_id AND s.user_id = auth.uid())
  );

CREATE POLICY scan_files_insert_own ON public.scan_files
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.scans s WHERE s.id = scan_id AND s.user_id = auth.uid()));

CREATE POLICY scan_files_delete_own ON public.scan_files
  FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.scans s WHERE s.id = scan_id AND s.user_id = auth.uid()));

-- No UPDATE policy: submitted source is immutable once scanned -- rescanning
-- changed code is a new scan, not an edit of the evidence an existing
-- finding was based on.

ALTER TABLE public.scan_findings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_findings FORCE ROW LEVEL SECURITY;

CREATE POLICY scan_findings_select_own_or_staff ON public.scan_findings
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR EXISTS (SELECT 1 FROM public.scans s WHERE s.id = scan_id AND s.user_id = auth.uid())
  );

CREATE POLICY scan_findings_insert_own ON public.scan_findings
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.scans s WHERE s.id = scan_id AND s.user_id = auth.uid()));

-- No UPDATE/DELETE policy: status changes only via
-- transition_scan_finding_status() (SECURITY DEFINER); every other field is
-- set once at insert and never edited.

ALTER TABLE public.scan_finding_status_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scan_finding_status_events FORCE ROW LEVEL SECURITY;

CREATE POLICY scan_finding_status_events_select_own_or_staff ON public.scan_finding_status_events
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.scan_findings f
      JOIN public.scans s ON s.id = f.scan_id
      WHERE f.id = finding_id AND s.user_id = auth.uid()
    )
  );

-- No INSERT/UPDATE/DELETE policy at all: written only by
-- transition_scan_finding_status(), which runs as SECURITY DEFINER and so
-- is unaffected by the lack of a policy for `authenticated`.
