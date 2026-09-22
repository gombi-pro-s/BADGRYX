-- ============================================================================
-- Fixes a real, previously-latent bug: deleting a user from auth.users
-- (whether through the GoTrue Admin API for a real "delete my account"
-- flow, or directly in the Supabase dashboard) would fail outright with a
-- foreign key violation for almost any account that has ever done anything
-- meaningful on this platform. Every user-OWNED row (skill_evidence,
-- quiz_attempts, lab_instances, ...) already cascades correctly -- that
-- part of the schema was right from day one. The bug is in the 8
-- ATTRIBUTION columns below: "who granted this role", "who created this
-- org", "who reviewed this capstone", "who performed this audited action".
-- Each references auth.users with no ON DELETE action at all, which
-- Postgres defaults to NO ACTION -- i.e. it blocks the delete.
--
-- The fix is ON DELETE SET NULL, not CASCADE: the role grant, the
-- organization, the audit log entry, the capstone review -- none of that
-- should be destroyed just because the person who did it later deleted
-- their own account. That would be actively wrong for audit_log
-- specifically (the whole point of an audit trail is that it survives the
-- actor). The record survives; only the now-dangling identity reference
-- becomes NULL.
--
-- Two of these columns (organizations.created_by,
-- organization_invitations.invited_by) were NOT NULL, which is
-- incompatible with SET NULL -- both become nullable here. Nothing in
-- application code relies on either being non-null after the fact (the
-- NOT NULL was only ever meaningful at INSERT time, and RLS's
-- organizations_insert_self policy already requires created_by = auth.uid()
-- for an authenticated caller regardless of column nullability).
-- ============================================================================

ALTER TABLE public.audit_log
  DROP CONSTRAINT audit_log_actor_id_fkey,
  ADD CONSTRAINT audit_log_actor_id_fkey
    FOREIGN KEY (actor_id) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.capstone_submissions
  DROP CONSTRAINT capstone_submissions_reviewer_id_fkey,
  ADD CONSTRAINT capstone_submissions_reviewer_id_fkey
    FOREIGN KEY (reviewer_id) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.learning_paths
  DROP CONSTRAINT learning_paths_created_by_fkey,
  ADD CONSTRAINT learning_paths_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.organization_members
  DROP CONSTRAINT organization_members_invited_by_fkey,
  ADD CONSTRAINT organization_members_invited_by_fkey
    FOREIGN KEY (invited_by) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.subscriptions
  DROP CONSTRAINT subscriptions_granted_by_fkey,
  ADD CONSTRAINT subscriptions_granted_by_fkey
    FOREIGN KEY (granted_by) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.user_roles
  DROP CONSTRAINT user_roles_granted_by_fkey,
  ADD CONSTRAINT user_roles_granted_by_fkey
    FOREIGN KEY (granted_by) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.organizations
  ALTER COLUMN created_by DROP NOT NULL,
  DROP CONSTRAINT organizations_created_by_fkey,
  ADD CONSTRAINT organizations_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES auth.users (id) ON DELETE SET NULL;

ALTER TABLE public.organization_invitations
  ALTER COLUMN invited_by DROP NOT NULL,
  DROP CONSTRAINT organization_invitations_invited_by_fkey,
  ADD CONSTRAINT organization_invitations_invited_by_fkey
    FOREIGN KEY (invited_by) REFERENCES auth.users (id) ON DELETE SET NULL;
