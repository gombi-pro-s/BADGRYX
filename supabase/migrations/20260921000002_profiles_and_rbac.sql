-- ============================================================================
-- Identity: profiles + platform-wide RBAC.
--
-- Design decisions (see docs/adr/0002-rbac-model.md):
--   * `profiles` holds user-editable, non-privileged data only. It never
--     stores a role column, so a user can never grant themselves a role by
--     updating their own profile row.
--   * `user_roles` is the single source of truth for platform-wide roles
--     (student/instructor/moderator/admin). Only an existing admin, or the
--     server using the service_role key, may write to it (enforced by RLS
--     in 20260921000005_identity_rls_policies.sql).
--   * `public.has_role()` / `public.is_admin()` are SECURITY DEFINER helper
--     functions owned by the migration-running superuser, so they can read
--     user_roles to answer "does the CURRENT caller have role X" without
--     being blocked by user_roles' own RLS policies, and without letting
--     callers pass an arbitrary target user id (they always check auth.uid()
--     internally) -- which is what prevents them being usable to probe other
--     users' roles.
-- ============================================================================

CREATE TYPE public.platform_role AS ENUM (
  'user',
  'instructor',
  'moderator',
  'admin'
);

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  username citext UNIQUE,
  display_name text,
  avatar_url text,
  bio text,
  country text,
  timezone text NOT NULL DEFAULT 'UTC',
  locale text NOT NULL DEFAULT 'en',
  career_goal text,
  onboarding_completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT username_format CHECK (
    username IS NULL OR username ~ '^[a-zA-Z0-9_-]{3,32}$'
  )
);

COMMENT ON TABLE public.profiles IS
  'User-editable profile data. Never stores authorization state -- see user_roles.';

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role public.platform_role NOT NULL,
  granted_by uuid REFERENCES auth.users (id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

COMMENT ON TABLE public.user_roles IS
  'Source of truth for platform-wide RBAC. Every user implicitly has ''user''; '
  'elevated roles must be explicitly granted by an admin or by the server '
  'using the service_role key (e.g. an approved instructor application).';

CREATE INDEX user_roles_user_id_idx ON public.user_roles (user_id);

-- ----------------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER, owned by the migration role so they
-- bypass RLS on user_roles; always scoped to auth.uid(), never a caller-
-- supplied user id, so they cannot be used to enumerate other users' roles).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.has_role(check_role public.platform_role)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = check_role
  ) OR (check_role = 'user' AND auth.uid() IS NOT NULL);
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT public.has_role('admin');
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT public.has_role('admin') OR public.has_role('moderator');
$$;

COMMENT ON FUNCTION public.has_role(public.platform_role) IS
  'True if the CURRENT authenticated caller (auth.uid()) holds the given platform role.';

-- ----------------------------------------------------------------------------
-- New-user provisioning: every new auth.users row gets a profile and the
-- baseline 'user' role automatically. This runs as the trigger owner
-- (postgres), so it is unaffected by RLS.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)))
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'user')
  ON CONFLICT (user_id, role) DO NOTHING;

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER profiles_set_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
