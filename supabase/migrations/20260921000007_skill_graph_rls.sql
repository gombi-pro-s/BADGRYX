-- ============================================================================
-- RLS: Skill Graph.
-- ============================================================================

ALTER TABLE public.skill_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_categories FORCE ROW LEVEL SECURITY;

CREATE POLICY skill_categories_select_all ON public.skill_categories
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY skill_categories_admin_write ON public.skill_categories
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

ALTER TABLE public.skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skills FORCE ROW LEVEL SECURITY;

CREATE POLICY skills_select_all ON public.skills
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY skills_admin_write ON public.skills
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

ALTER TABLE public.skill_prerequisites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_prerequisites FORCE ROW LEVEL SECURITY;

CREATE POLICY skill_prereqs_select_all ON public.skill_prerequisites
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY skill_prereqs_admin_write ON public.skill_prerequisites
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ----------------------------------------------------------------------------
-- skill_evidence / user_skill_states: readable by the owning user, by
-- instructors/admins (platform-wide), and by org_admins of an org the user
-- belongs to (so an instructor can see their students' real progress).
-- No INSERT/UPDATE/DELETE policy exists for authenticated/anon at all --
-- writes only happen through the SECURITY DEFINER grading functions, which
-- run as the (superuser) function owner and are therefore unaffected by
-- these policies.
-- ----------------------------------------------------------------------------

ALTER TABLE public.skill_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_evidence FORCE ROW LEVEL SECURITY;

CREATE POLICY skill_evidence_select_own_or_staff ON public.skill_evidence
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target
        ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = skill_evidence.user_id
    )
  );

ALTER TABLE public.user_skill_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_skill_states FORCE ROW LEVEL SECURITY;

CREATE POLICY user_skill_states_select_own_or_staff ON public.user_skill_states
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target
        ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = user_skill_states.user_id
    )
  );
