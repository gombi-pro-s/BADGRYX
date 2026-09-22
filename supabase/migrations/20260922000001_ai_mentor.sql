-- ============================================================================
-- AI Security Mentor (section 11): conversation history, scoped to the
-- owner. The Mentor is read-only with respect to the Skill Graph -- it can
-- explain, hint, teach, and analyze failures using real data pulled by the
-- application layer, but it never writes skill_evidence or any grading
-- table. Only the deterministic grading RPCs
-- (submit_quiz_attempt/submit_lab_flag/submit_ctf_flag) can do that. This
-- is what makes "the AI must never fabricate lab state, findings, evidence
-- or scan results" structurally true rather than just a prompt instruction:
-- there is no table grant that would let it.
-- ============================================================================

CREATE TYPE public.mentor_context_type AS ENUM ('skill', 'lesson', 'lab', 'ctf', 'general');
CREATE TYPE public.mentor_mode AS ENUM (
  'explain', 'hint', 'teach', 'analyze_failure',
  'explain_command', 'explain_finding', 'explain_code', 'guide_investigation',
  'review_methodology', 'generate_quiz', 'prepare_assessment',
  'explain_remediation', 'review_report'
);
CREATE TYPE public.mentor_message_role AS ENUM ('user', 'assistant');

CREATE TABLE public.mentor_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  context_type public.mentor_context_type NOT NULL DEFAULT 'general',
  context_id uuid,
  title text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX mentor_conversations_user_id_idx ON public.mentor_conversations (user_id, updated_at DESC);

CREATE TABLE public.mentor_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.mentor_conversations (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role public.mentor_message_role NOT NULL,
  mode public.mentor_mode,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX mentor_messages_conversation_id_idx ON public.mentor_messages (conversation_id, created_at);
CREATE INDEX mentor_messages_user_id_created_idx ON public.mentor_messages (user_id, created_at);

COMMENT ON TABLE public.mentor_messages IS
  'user_id is denormalized onto every message (not just the parent '
  'conversation) so the daily-quota query (count this user''s messages '
  'since midnight) is a single indexed scan, not a join.';

CREATE TRIGGER mentor_conversations_set_updated_at
  BEFORE UPDATE ON public.mentor_conversations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS: strictly owner-scoped, plus staff read access for support/abuse
-- review (matching the pattern used for skill_evidence/lab_progress).
-- Writes to mentor_messages happen via the server (service_role, from the
-- API route, after the Anthropic call succeeds) OR directly by the owner
-- for their own conversation -- either path is fine since there is no
-- grading consequence to a message existing; what matters is that nobody
-- can read or write another user's conversation.
-- ----------------------------------------------------------------------------

ALTER TABLE public.mentor_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mentor_conversations FORCE ROW LEVEL SECURITY;

CREATE POLICY mentor_conversations_select_own_or_staff ON public.mentor_conversations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY mentor_conversations_insert_own ON public.mentor_conversations
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY mentor_conversations_update_own ON public.mentor_conversations
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY mentor_conversations_delete_own ON public.mentor_conversations
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

ALTER TABLE public.mentor_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mentor_messages FORCE ROW LEVEL SECURITY;

CREATE POLICY mentor_messages_select_own_or_staff ON public.mentor_messages
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY mentor_messages_insert_own ON public.mentor_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.mentor_conversations c
      WHERE c.id = conversation_id AND c.user_id = auth.uid()
    )
  );

-- No UPDATE/DELETE policy on messages: a conversation transcript, once
-- written, is not editable -- consistent with treating it as an honest
-- record of what was actually asked and answered.
