-- ============================================================================
-- Announcements: staff-authored platform-wide notices, or instructor-
-- authored notices scoped to their own organization's members.
--
-- This is half of RELEASE_CHECKLIST's "Announcements, translations" gap.
-- Translations are deliberately NOT built alongside this: there is no i18n
-- framework yet (no locale routing, no language switcher) to ever read a
-- translated string, so a translations table today would be inert
-- scaffolding with nothing consuming it -- see docs/adr/0017-announcements.md.
-- ============================================================================

CREATE TABLE public.announcements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES public.organizations (id) ON DELETE CASCADE,
  title text NOT NULL,
  body_markdown text NOT NULL,
  published boolean NOT NULL DEFAULT false,
  published_at timestamptz,
  expires_at timestamptz,
  created_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT announcements_title_not_blank CHECK (length(btrim(title)) > 0),
  CONSTRAINT announcements_body_not_blank CHECK (length(btrim(body_markdown)) > 0)
);

COMMENT ON COLUMN public.announcements.organization_id IS
  'NULL = platform-wide (staff-authored). Non-null = scoped to that '
  'organization''s own members, authored by one of its instructors/admins. '
  'ON DELETE CASCADE: an announcement scoped to a deleted org is meaningless '
  '-- this is an ownership FK (ADR 0012), unlike created_by below.';

COMMENT ON COLUMN public.announcements.created_by IS
  'ON DELETE SET NULL: attribution only (ADR 0012) -- the announcement '
  'itself stays if its author''s account is later deleted.';

CREATE INDEX announcements_org_id_idx ON public.announcements (organization_id);
CREATE INDEX announcements_published_idx ON public.announcements (published, published_at DESC);

CREATE TRIGGER announcements_set_updated_at
  BEFORE UPDATE ON public.announcements
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Helper: is the current user an instructor/team_owner/org_admin of the
-- given org? Mirrors is_org_admin() (20260921000003_organizations_teams.sql)
-- but also includes the 'instructor' role -- "post a notice to my class" is
-- exactly the kind of authority an instructor should have without needing
-- team_owner/org_admin's membership-management authority.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_org_instructor(org_id uuid)
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
      AND role IN ('instructor', 'team_owner', 'org_admin')
  );
$$;

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Read: staff see everything (moderation across every org); an org's own
-- instructors+ see that org's drafts too (so they can preview before
-- publishing); everyone else sees only published, non-expired announcements
-- that are either platform-wide or scoped to an org they belong to.
CREATE POLICY announcements_select ON public.announcements
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR (organization_id IS NOT NULL AND public.is_org_instructor(organization_id))
    OR (
      published
      AND (expires_at IS NULL OR expires_at > now())
      AND (organization_id IS NULL OR public.is_org_member(organization_id))
    )
  );

-- Write: staff manage platform-wide announcements (organization_id IS
-- NULL); an org's own instructors+ manage that org's announcements. Nobody
-- can write a platform-wide announcement without being staff, and nobody
-- can write into an org they have no instructor-level standing in --
-- exactly mirroring how learning_paths_staff_write and org_members_write_*
-- gate their own tables.
CREATE POLICY announcements_write ON public.announcements
  FOR ALL TO authenticated
  USING (
    (organization_id IS NULL AND public.is_staff())
    OR (organization_id IS NOT NULL AND public.is_org_instructor(organization_id))
  )
  WITH CHECK (
    (organization_id IS NULL AND public.is_staff())
    OR (organization_id IS NOT NULL AND public.is_org_instructor(organization_id))
  );
