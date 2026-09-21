-- ============================================================================
-- Row Level Security: identity, RBAC, organizations, audit log.
--
-- Default posture for every table in this platform: RLS ENABLED, no policy
-- grants access unless explicitly written below. service_role (used only by
-- trusted server-side code, never shipped to a client) bypasses RLS
-- entirely by role attribute (BYPASSRLS), so it needs no explicit policies.
-- ============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles FORCE ROW LEVEL SECURITY;

-- Any authenticated user can read any profile (usernames/avatars are public
-- within the product, e.g. leaderboards) but only the owner can write it,
-- and the owner can never touch role/authorization columns because those
-- live in user_roles, not profiles.
CREATE POLICY profiles_select_authenticated ON public.profiles
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE POLICY profiles_admin_all ON public.profiles
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- user_roles: this is the table a privilege-escalation exploit would target.
-- Users may READ their own role assignments (so the UI can show "you are an
-- instructor"), but only an admin (or service_role, which bypasses RLS) may
-- INSERT/UPDATE/DELETE. There is deliberately no policy letting a user
-- insert/update their own row -- self-service role grants must not exist.
-- ----------------------------------------------------------------------------

ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles FORCE ROW LEVEL SECURITY;

CREATE POLICY user_roles_select_own_or_admin ON public.user_roles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

CREATE POLICY user_roles_admin_write ON public.user_roles
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

CREATE POLICY user_roles_admin_update ON public.user_roles
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY user_roles_admin_delete ON public.user_roles
  FOR DELETE TO authenticated
  USING (public.is_admin());

-- ----------------------------------------------------------------------------
-- organizations
-- ----------------------------------------------------------------------------

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations FORCE ROW LEVEL SECURITY;

CREATE POLICY organizations_select_member ON public.organizations
  FOR SELECT TO authenticated
  USING (public.is_org_member(id));

CREATE POLICY organizations_insert_self ON public.organizations
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY organizations_update_org_admin ON public.organizations
  FOR UPDATE TO authenticated
  USING (public.is_org_admin(id))
  WITH CHECK (public.is_org_admin(id));

CREATE POLICY organizations_delete_org_admin ON public.organizations
  FOR DELETE TO authenticated
  USING (public.is_org_admin(id));

-- ----------------------------------------------------------------------------
-- organization_members: members can see their own org's roster; only an
-- org_admin/team_owner (or platform admin) can change membership/roles.
-- A member can never promote themselves -- there is no "update own row"
-- policy for the role column.
-- ----------------------------------------------------------------------------

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members FORCE ROW LEVEL SECURITY;

CREATE POLICY org_members_select_member ON public.organization_members
  FOR SELECT TO authenticated
  USING (public.is_org_member(organization_id));

CREATE POLICY org_members_write_org_admin ON public.organization_members
  FOR INSERT TO authenticated
  WITH CHECK (public.is_org_admin(organization_id));

CREATE POLICY org_members_update_org_admin ON public.organization_members
  FOR UPDATE TO authenticated
  USING (public.is_org_admin(organization_id))
  WITH CHECK (public.is_org_admin(organization_id));

CREATE POLICY org_members_delete_org_admin_or_self ON public.organization_members
  FOR DELETE TO authenticated
  USING (public.is_org_admin(organization_id) OR user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- organization_invitations: only org admins manage invitations. The raw
-- token is never stored (see column comment), so there is intentionally no
-- "select by token" policy here -- token verification happens server-side
-- via service_role against token_hash.
-- ----------------------------------------------------------------------------

ALTER TABLE public.organization_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_invitations FORCE ROW LEVEL SECURITY;

CREATE POLICY org_invitations_select_org_admin ON public.organization_invitations
  FOR SELECT TO authenticated
  USING (public.is_org_admin(organization_id));

CREATE POLICY org_invitations_write_org_admin ON public.organization_invitations
  FOR INSERT TO authenticated
  WITH CHECK (public.is_org_admin(organization_id));

CREATE POLICY org_invitations_update_org_admin ON public.organization_invitations
  FOR UPDATE TO authenticated
  USING (public.is_org_admin(organization_id))
  WITH CHECK (public.is_org_admin(organization_id));

CREATE POLICY org_invitations_delete_org_admin ON public.organization_invitations
  FOR DELETE TO authenticated
  USING (public.is_org_admin(organization_id));

-- ----------------------------------------------------------------------------
-- audit_log: immutable. Admins (platform-wide) can read everything; org
-- admins can read entries scoped to their own organization. Nobody gets
-- UPDATE or DELETE -- not even admins -- and INSERT only happens through
-- log_audit_event(), never through a direct table grant.
-- ----------------------------------------------------------------------------

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log FORCE ROW LEVEL SECURITY;

CREATE POLICY audit_log_select_admin ON public.audit_log
  FOR SELECT TO authenticated
  USING (
    public.is_admin()
    OR (organization_id IS NOT NULL AND public.is_org_admin(organization_id))
  );

-- No INSERT/UPDATE/DELETE policy is created for any non-service role:
-- combined with FORCE ROW LEVEL SECURITY and no matching policy, this makes
-- the table read-only-by-policy for everyone except service_role.
