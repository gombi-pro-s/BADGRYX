-- ============================================================================
-- Instructor dashboard, part 1: schema/RLS/functions.
--
-- 1. Extends the org-instructor RLS visibility branch (already used on
--    skill_evidence, user_skill_states, lab_instances, lab_progress -- see
--    20260921000007_skill_graph_rls.sql and 20260921000009_content_model_rls.sql)
--    to the 4 remaining gradeable-outcome tables: quiz_attempts,
--    ctf_submissions, capstone_submissions, investigation_submissions. An
--    instructor/team_owner/org_admin can now see a fellow org member's real
--    graded results the same way they can already see their skill states and
--    lab progress -- this is what makes an instructor dashboard possible
--    without a service-role bypass.
--
-- 2. Builds the organization_invitations lifecycle, which
--    20260921000003_organizations_teams.sql designed (token_hash column,
--    RLS policies) but never wired up: create_organization_invitation()
--    generates and hashes a random token (the org admin gets the raw token
--    back exactly once -- there is no email service in this app, so the UI
--    must show it for the admin to copy/share manually, same honesty as
--    the payment-provider deferral in ADR 0005), and
--    accept_organization_invitation() validates and redeems it.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Org-instructor visibility on the 4 remaining submission tables.
-- ----------------------------------------------------------------------------

DROP POLICY quiz_attempts_select_own_or_staff ON public.quiz_attempts;
CREATE POLICY quiz_attempts_select_own_staff_or_instructor ON public.quiz_attempts
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = quiz_attempts.user_id
    )
  );

DROP POLICY ctf_submissions_select_own_or_staff ON public.ctf_submissions;
CREATE POLICY ctf_submissions_select_own_staff_or_instructor ON public.ctf_submissions
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = ctf_submissions.user_id
    )
  );

DROP POLICY capstone_submissions_select_own_or_staff ON public.capstone_submissions;
CREATE POLICY capstone_submissions_select_own_staff_or_instructor ON public.capstone_submissions
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = capstone_submissions.user_id
    )
  );

DROP POLICY investigation_submissions_select_own_or_staff ON public.investigation_submissions;
CREATE POLICY investigation_submissions_select_own_staff_or_instructor ON public.investigation_submissions
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = investigation_submissions.user_id
    )
  );

-- Note: investigation_instances.notes is deliberately NOT extended here --
-- see 20260922000009_investigations.sql, it's a genuinely private scratchpad
-- not even staff can read, an intentional exception to this pattern.

-- ----------------------------------------------------------------------------
-- 2. create_organization_invitation: only an org admin/team owner may call
-- this (checked internally -- SECURITY DEFINER bypasses the table's own RLS,
-- so the function must re-check). Generates a random 256-bit token, stores
-- only its sha256 hash (mirrors the documented token_hash column comment),
-- and returns the raw token to the caller exactly once -- callers must
-- display/share it immediately, it can never be recovered afterward.
-- ----------------------------------------------------------------------------

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
  VALUES (p_organization_id, p_email, p_role, v_user_id, v_token_hash);

  RETURN v_raw_token;
END;
$$;

COMMENT ON FUNCTION public.create_organization_invitation(uuid, citext, public.org_role) IS
  'Only caller sees the raw token, and only once -- store it (token_hash) '
  'the same way password-reset tokens are stored, never retrievable again.';

REVOKE ALL ON FUNCTION public.create_organization_invitation FROM public;
GRANT EXECUTE ON FUNCTION public.create_organization_invitation TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. accept_organization_invitation: redeems a raw token. Independently
-- verifies not-revoked, not-already-accepted, not-expired, and that the
-- accepting account's email matches the invited email, before inserting
-- membership -- exactly the "server-side re-verification, no client-trusted
-- state" discipline used by every grading function in this schema.
-- ----------------------------------------------------------------------------

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

  RETURN v_member;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_organization_invitation FROM public;
GRANT EXECUTE ON FUNCTION public.accept_organization_invitation TO authenticated, service_role;
