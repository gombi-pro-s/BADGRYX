-- ============================================================================
-- Organizations / Teams
--
-- An organization is a paying customer (company, school, team) that groups
-- learners under an instructor/team-owner/org-admin hierarchy, separate from
-- the platform-wide RBAC in user_roles. Org-scoped roles only grant
-- authority *within that organization* (e.g. an org_admin can manage that
-- org's members and see their skill/lab progress, but is not a platform
-- admin).
-- ============================================================================

CREATE TYPE public.org_role AS ENUM (
  'member',
  'instructor',
  'team_owner',
  'org_admin'
);

CREATE TABLE public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug citext NOT NULL UNIQUE,
  name text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users (id),
  seat_limit integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9-]{3,64}$')
);

CREATE TABLE public.organization_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  role public.org_role NOT NULL DEFAULT 'member',
  invited_by uuid REFERENCES auth.users (id),
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id)
);

CREATE INDEX organization_members_user_id_idx ON public.organization_members (user_id);
CREATE INDEX organization_members_org_id_idx ON public.organization_members (organization_id);

CREATE TABLE public.organization_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations (id) ON DELETE CASCADE,
  email citext NOT NULL,
  role public.org_role NOT NULL DEFAULT 'member',
  invited_by uuid NOT NULL REFERENCES auth.users (id),
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '14 days'),
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.organization_invitations.token_hash IS
  'sha256 of the invitation token. The raw token is only ever emailed to the '
  'invitee and is never stored -- mirrors the password-reset-token pattern.';

CREATE INDEX organization_invitations_org_id_idx ON public.organization_invitations (organization_id);
CREATE INDEX organization_invitations_email_idx ON public.organization_invitations (email);

-- ----------------------------------------------------------------------------
-- Helper: is the current user an org_admin/team_owner of the given org?
-- SECURITY DEFINER for the same reason as public.has_role() above: it must
-- read organization_members regardless of that table's own RLS policy, and
-- it always keys off auth.uid(), never a caller-supplied user id.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_org_admin(org_id uuid)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT public.is_admin() OR EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE organization_id = org_id
      AND user_id = auth.uid()
      AND role IN ('team_owner', 'org_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT public.is_admin() OR EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE organization_id = org_id AND user_id = auth.uid()
  );
$$;

CREATE TRIGGER organizations_set_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Creating an organization automatically makes the creator its team_owner.
CREATE OR REPLACE FUNCTION public.handle_new_organization()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.organization_members (organization_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'team_owner');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_organization_created
  AFTER INSERT ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_organization();
