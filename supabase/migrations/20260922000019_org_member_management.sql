-- ============================================================================
-- Org member management: change a member's role, or remove them.
--
-- The RLS policies on organization_members (org_members_update_org_admin,
-- org_members_delete_org_admin_or_self) already permit an org admin to
-- change any member's role or remove them, and a member to remove
-- themselves. That's real enforcement, but it has no invariant: nothing
-- stops an org_admin from demoting or removing the organization's only
-- team_owner, which would leave the org with no one able to manage it at
-- all (short of a platform admin or a service_role database edit).
--
-- Mirrors grant_platform_role()/revoke_platform_role()
-- (20260922000016_admin_user_role_management.sql): one SECURITY DEFINER
-- function per write, audit-logged, with the state-transition guard the
-- raw RLS policies can't express. The direct RLS write path is left in
-- place for the same reasons documented there; this app's own UI is built
-- exclusively on these two functions.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_organization_member_role(
  p_organization_id uuid,
  p_organization_member_id uuid,
  p_new_role public.org_role
)
  RETURNS public.organization_members
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_member public.organization_members;
  v_owner_count int;
BEGIN
  IF NOT public.is_org_admin(p_organization_id) THEN
    RAISE EXCEPTION 'only an org admin or team owner can change a member''s role' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_member FROM public.organization_members
    WHERE id = p_organization_member_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'that member does not belong to this organization' USING ERRCODE = 'P0002';
  END IF;

  IF v_member.role = 'team_owner' AND p_new_role <> 'team_owner' THEN
    SELECT count(*) INTO v_owner_count FROM public.organization_members
      WHERE organization_id = p_organization_id AND role = 'team_owner';
    IF v_owner_count <= 1 THEN
      RAISE EXCEPTION 'cannot demote the last team owner -- promote another member first' USING ERRCODE = 'P0010';
    END IF;
  END IF;

  UPDATE public.organization_members SET role = p_new_role
    WHERE id = p_organization_member_id
    RETURNING * INTO v_member;

  PERFORM public.log_audit_event('org.member.role_changed', 'organization_member', p_organization_member_id::text,
    p_organization_id, jsonb_build_object('user_id', v_member.user_id, 'new_role', p_new_role));

  RETURN v_member;
END;
$$;

REVOKE ALL ON FUNCTION public.update_organization_member_role FROM public;
GRANT EXECUTE ON FUNCTION public.update_organization_member_role TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.remove_organization_member(
  p_organization_id uuid,
  p_organization_member_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_member public.organization_members;
  v_owner_count int;
BEGIN
  SELECT * INTO v_member FROM public.organization_members
    WHERE id = p_organization_member_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'that member does not belong to this organization' USING ERRCODE = 'P0002';
  END IF;

  IF NOT (public.is_org_admin(p_organization_id) OR v_member.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'only an org admin, team owner, or the member themselves can remove this membership'
      USING ERRCODE = '42501';
  END IF;

  IF v_member.role = 'team_owner' THEN
    SELECT count(*) INTO v_owner_count FROM public.organization_members
      WHERE organization_id = p_organization_id AND role = 'team_owner';
    IF v_owner_count <= 1 THEN
      RAISE EXCEPTION 'cannot remove the last team owner -- promote another member first' USING ERRCODE = 'P0010';
    END IF;
  END IF;

  DELETE FROM public.organization_members WHERE id = p_organization_member_id;

  PERFORM public.log_audit_event('org.member.removed', 'organization_member', p_organization_member_id::text,
    p_organization_id, jsonb_build_object('user_id', v_member.user_id, 'role', v_member.role,
      'self', v_member.user_id = auth.uid()));
END;
$$;

REVOKE ALL ON FUNCTION public.remove_organization_member FROM public;
GRANT EXECUTE ON FUNCTION public.remove_organization_member TO authenticated, service_role;
