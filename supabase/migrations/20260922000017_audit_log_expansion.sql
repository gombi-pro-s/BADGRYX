-- ============================================================================
-- Audit log coverage expansion, part 1: the organization invitation
-- lifecycle. create_organization_invitation()/accept_organization_invitation()
-- (20260922000012_org_instructor_visibility_and_invitations.sql) have
-- logged nothing since they were written -- a real gap, and a meaningful
-- one: audit_log_select_admin already lets an org admin read entries
-- scoped to their own organization_id (see
-- 20260921000005_identity_rls_policies.sql), which these functions never
-- populated, so an org admin had no way to see "who was invited, when, by
-- whom, and who actually joined" even though the RLS to show them that
-- already existed.
--
-- Straight CREATE OR REPLACE -- everything else is identical to
-- 20260922000012's versions.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_organization_invitation(
  p_organization_id uuid,
  p_email citext,
  p_role public.org_role DEFAULT 'member'
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_seat_limit int;
  v_seats_used int;
  v_raw_token text;
  v_token_hash text;
  v_invitation_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  IF NOT public.is_org_admin(p_organization_id) THEN
    RAISE EXCEPTION 'only an org admin or team owner can invite members' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.organization_members om
    JOIN auth.users u ON u.id = om.user_id
    WHERE om.organization_id = p_organization_id AND u.email = p_email
  ) THEN
    RAISE EXCEPTION 'that person is already a member of this organization' USING ERRCODE = 'P0004';
  END IF;

  SELECT seat_limit INTO v_seat_limit FROM public.organizations WHERE id = p_organization_id;
  IF v_seat_limit IS NOT NULL THEN
    SELECT
      (SELECT count(*) FROM public.organization_members WHERE organization_id = p_organization_id)
      + (SELECT count(*) FROM public.organization_invitations
           WHERE organization_id = p_organization_id
             AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now())
      INTO v_seats_used;
    IF v_seats_used >= v_seat_limit THEN
      RAISE EXCEPTION 'organization seat limit (%) reached' , v_seat_limit USING ERRCODE = 'P0005';
    END IF;
  END IF;

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');

  INSERT INTO public.organization_invitations (organization_id, email, role, invited_by, token_hash)
  VALUES (p_organization_id, p_email, p_role, v_user_id, v_token_hash)
  RETURNING id INTO v_invitation_id;

  PERFORM public.log_audit_event('org.invitation.created', 'organization_invitation', v_invitation_id::text,
    p_organization_id, jsonb_build_object('email', p_email, 'role', p_role));

  RETURN v_raw_token;
END;
$$;

COMMENT ON FUNCTION public.create_organization_invitation(uuid, citext, public.org_role) IS
  'Only caller sees the raw token, and only once -- store it (token_hash) '
  'the same way password-reset tokens are stored, never retrievable again.';

REVOKE ALL ON FUNCTION public.create_organization_invitation FROM public;
GRANT EXECUTE ON FUNCTION public.create_organization_invitation TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.accept_organization_invitation(p_token text)
  RETURNS public.organization_members
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_email citext;
  v_invite public.organization_invitations;
  v_member public.organization_members;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_invite FROM public.organization_invitations
    WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found or invalid' USING ERRCODE = 'P0002';
  END IF;

  IF v_invite.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'this invitation has been revoked' USING ERRCODE = 'P0006';
  END IF;
  IF v_invite.accepted_at IS NOT NULL THEN
    RAISE EXCEPTION 'this invitation has already been accepted' USING ERRCODE = 'P0007';
  END IF;
  IF v_invite.expires_at < now() THEN
    RAISE EXCEPTION 'this invitation has expired' USING ERRCODE = 'P0008';
  END IF;

  SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
  IF v_user_email IS DISTINCT FROM v_invite.email THEN
    RAISE EXCEPTION 'this invitation was sent to a different email address' USING ERRCODE = 'P0009';
  END IF;

  INSERT INTO public.organization_members (organization_id, user_id, role, invited_by)
  VALUES (v_invite.organization_id, v_user_id, v_invite.role, v_invite.invited_by)
  ON CONFLICT (organization_id, user_id) DO UPDATE SET role = EXCLUDED.role
  RETURNING * INTO v_member;

  UPDATE public.organization_invitations SET accepted_at = now() WHERE id = v_invite.id;

  PERFORM public.log_audit_event('org.invitation.accepted', 'organization_member', v_member.id::text,
    v_invite.organization_id, jsonb_build_object('role', v_member.role));

  RETURN v_member;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_organization_invitation FROM public;
GRANT EXECUTE ON FUNCTION public.accept_organization_invitation TO authenticated, service_role;
