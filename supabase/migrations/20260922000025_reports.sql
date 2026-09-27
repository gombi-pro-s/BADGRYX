-- ============================================================================
-- Reports: a learner writes a freeform pentest report or methodology
-- write-up and asks the AI Mentor to critique it. This is the feature
-- RELEASE_CHECKLIST's REVIEW_REPORT/REVIEW_METHODOLOGY Mentor modes were
-- stubbed against ("this platform's written-report generation feature is
-- not implemented yet") -- those modes and their prompt logic already
-- existed (see lib/mentor/prompt.ts), there was simply nothing for them to
-- review.
--
-- This is deliberately separate from capstone_submissions.report_content,
-- which already exists and is reviewed by a human staff member
-- (review_capstone_submission(), ADR 0008) as part of a graded capstone.
-- A `reports` row is personal practice, reviewed only by the Mentor, never
-- graded, and never produces skill_evidence -- exactly like every other
-- Mentor conversation (the Mentor cannot write skill_evidence at all; see
-- 20260922000001_ai_mentor.sql's header comment).
-- ============================================================================

CREATE TYPE public.report_kind AS ENUM ('pentest_report', 'methodology');

CREATE TABLE public.reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  kind public.report_kind NOT NULL DEFAULT 'pentest_report',
  title text NOT NULL,
  content_markdown text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reports_title_not_blank CHECK (length(btrim(title)) > 0)
);

CREATE INDEX reports_user_id_idx ON public.reports (user_id, updated_at DESC);

CREATE TRIGGER reports_set_updated_at
  BEFORE UPDATE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports FORCE ROW LEVEL SECURITY;

-- Mirrors mentor_conversations' own policy shape exactly: staff can read
-- for moderation, but only the owner ever writes.
CREATE POLICY reports_select_own_or_staff ON public.reports
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY reports_insert_own ON public.reports
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY reports_update_own ON public.reports
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY reports_delete_own ON public.reports
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- Wires 'report' into the Mentor's existing focus-context taxonomy, the
-- same shape as the earlier 'investigation'/'finding' additions.
-- ----------------------------------------------------------------------------
ALTER TYPE public.mentor_context_type ADD VALUE 'report';
