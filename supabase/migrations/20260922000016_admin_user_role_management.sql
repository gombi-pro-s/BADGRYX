-- ============================================================================
-- Admin UI for granting/revoking platform roles. Until now the only write
-- path was a direct client INSERT/DELETE against user_roles (RLS already
-- permitted it -- user_roles_admin_write/_update/_delete), which is why
-- this worked "only directly in the database": there was no UI built on
-- top of it, no audit trail, and a real risk was unguarded -- an admin
-- could accidentally revoke their own admin role with no one left able to
-- grant it back (short of a service_role database edit).
--
-- grant_platform_role()/revoke_platform_role() become the only way this
-- app's own UI changes roles: each is audit-logged, and revoke blocks an
-- admin from revoking their own admin role. The direct RLS write path is
-- left in place (service_role tooling, migrations, and a genuine admin
-- emergency fallback still need it) -- this mirrors capstone review, which
-- narrowed to one function only because its status field needed real
-- state-transition validation user_roles doesn't have.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.grant_platform_role(p_user_id uuid, p_role public.platform_role)
  RETURNS public.user_roles
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.user_roles;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'only an admin can grant a platform role' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.user_roles (user_id, role, granted_by)
  VALUES (p_user_id, p_role, auth.uid())
  ON CONFLICT (user_id, role) DO UPDATE SET granted_by = EXCLUDED.granted_by
  RETURNING * INTO v_row;

  PERFORM public.log_audit_event('user_role.granted', 'user', p_user_id::text, NULL,
    jsonb_build_object('role', p_role));

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_platform_role FROM public;
GRANT EXECUTE ON FUNCTION public.grant_platform_role TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.revoke_platform_role(p_user_id uuid, p_role public.platform_role)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'only an admin can revoke a platform role' USING ERRCODE = '42501';
  END IF;
  IF p_user_id = auth.uid() AND p_role = 'admin' THEN
    RAISE EXCEPTION 'cannot revoke your own admin role -- ask another admin' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = p_user_id AND role = p_role;

  PERFORM public.log_audit_event('user_role.revoked', 'user', p_user_id::text, NULL,
    jsonb_build_object('role', p_role));
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_platform_role FROM public;
GRANT EXECUTE ON FUNCTION public.revoke_platform_role TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- admin_search_users: profiles has no email column by design (see
-- 20260921000002_profiles_and_rbac.sql -- it never stores authorization or
-- account-identity state), so finding a user to promote needs auth.users,
-- which the client can never query directly (not part of the public
-- schema's RLS-governed surface at all). This function is the one
-- admin-only, narrowly-scoped read across that boundary -- it returns
-- email/username/display_name/current roles, nothing else (no password
-- hash, no raw_user_meta_data), and re-checks is_admin() itself exactly
-- like every other SECURITY DEFINER function here.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_search_users(p_query text DEFAULT '')
  RETURNS TABLE (
    user_id uuid,
    email text,
    username text,
    display_name text,
    roles public.platform_role[]
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'only an admin can search users' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    u.email::text,
    p.username::text,
    p.display_name,
    COALESCE(
      array_agg(ur.role ORDER BY ur.role) FILTER (WHERE ur.role IS NOT NULL AND ur.role <> 'user'),
      ARRAY[]::public.platform_role[]
    )
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  LEFT JOIN public.user_roles ur ON ur.user_id = u.id
  WHERE
    trim(p_query) = ''
    OR u.email ILIKE '%' || p_query || '%'
    OR p.username ILIKE '%' || p_query || '%'
    OR p.display_name ILIKE '%' || p_query || '%'
  GROUP BY u.id, u.email, p.username, p.display_name
  ORDER BY u.email
  LIMIT 50;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_search_users FROM public;
GRANT EXECUTE ON FUNCTION public.admin_search_users TO authenticated, service_role;
