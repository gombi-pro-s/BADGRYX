-- ============================================================================
-- Fixes a real, previously-undiscovered gap: subscriptions.subject_id is a
-- polymorphic column (either auth.users.id or organizations.id, depending
-- on subject_type) and so structurally cannot carry a normal foreign key.
-- ADR 0012's account-deletion work fixed every *attribution* column
-- referencing auth.users (granted_by, created_by, etc.) but subject_id is
-- neither of ADR 0012's two categories -- it's not attribution (a record of
-- who did something) and it's not a normal FK-backed ownership column
-- either. It's the subject itself, just without a constraint enforcing that.
--
-- Confirmed by direct reproduction against the local test DB: inserting a
-- subscription for a user, then deleting that user from auth.users,
-- leaves the subscription row behind untouched -- no FK violation (nothing
-- to violate), no cleanup, an orphan forever.
--
-- Fix: two AFTER DELETE triggers, mirroring the existing AFTER INSERT
-- triggers on auth.users/organizations that already exist for the same
-- tables (handle_new_user, handle_new_user_free_plan, handle_new_organization
-- -- see 20260921000002_profiles_and_rbac.sql, 20260921000011_entitlements.sql,
-- 20260921000003_organizations_teams.sql). A subscription's subject_id is
-- ownership, not attribution -- the row's entire reason to exist is that
-- specific user or organization -- so deleting it (not nulling a column) is
-- the correct behavior, the same as every other CASCADE-owned row.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_deleted_user_subscriptions()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.subscriptions WHERE subject_type = 'user' AND subject_id = OLD.id;
  RETURN OLD;
END;
$$;

CREATE TRIGGER on_auth_user_deleted_cleanup_subscriptions
  AFTER DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_deleted_user_subscriptions();

CREATE OR REPLACE FUNCTION public.handle_deleted_organization_subscriptions()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.subscriptions WHERE subject_type = 'organization' AND subject_id = OLD.id;
  RETURN OLD;
END;
$$;

CREATE TRIGGER on_organization_deleted_cleanup_subscriptions
  AFTER DELETE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.handle_deleted_organization_subscriptions();
