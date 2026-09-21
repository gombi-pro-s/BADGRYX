-- ============================================================================
-- Security / audit log (section 34).
--
-- Append-only: no UPDATE or DELETE grant exists for any non-service role,
-- and even INSERT is not granted directly -- all writes go through
-- public.log_audit_event(), which stamps actor/time itself so a caller can
-- never forge who performed an action or backdate an entry.
-- ============================================================================

CREATE TABLE public.audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid REFERENCES auth.users (id),
  actor_role text,
  action text NOT NULL,
  target_type text,
  target_id text,
  organization_id uuid REFERENCES public.organizations (id),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.audit_log IS
  'Append-only security/audit trail. Never log passwords, tokens, API keys, '
  'flags, or full request/response bodies -- see docs/adr/0006-audit-logging.md.';

CREATE INDEX audit_log_actor_id_idx ON public.audit_log (actor_id);
CREATE INDEX audit_log_action_idx ON public.audit_log (action);
CREATE INDEX audit_log_org_id_idx ON public.audit_log (organization_id);
CREATE INDEX audit_log_created_at_idx ON public.audit_log (created_at DESC);

CREATE OR REPLACE FUNCTION public.log_audit_event(
  p_action text,
  p_target_type text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_organization_id uuid DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO public.audit_log (actor_id, actor_role, action, target_type, target_id, organization_id, metadata)
  VALUES (auth.uid(), auth.role(), p_action, p_target_type, p_target_id, p_organization_id, p_metadata)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.log_audit_event IS
  'The only sanctioned way to write to audit_log. Stamps actor_id/actor_role '
  'from the current session so entries cannot be forged by the caller.';

REVOKE ALL ON FUNCTION public.log_audit_event FROM public;
GRANT EXECUTE ON FUNCTION public.log_audit_event TO authenticated, service_role;
