-- ============================================================================
-- RLS: content model.
--
-- Recurring pattern: published content is publicly readable (anon +
-- authenticated); only staff (admin/moderator) can write it or see drafts.
-- Anything that would let a client fabricate proof of skill (quiz answer
-- keys, lab flags, hint unlocks, submission rows, progress rows) has NO
-- direct write grant for authenticated/anon at all -- see
-- 20260921000010_grading_and_evidence.sql for the only sanctioned write
-- path.
-- ============================================================================

-- ---- learning_paths / modules / lessons ------------------------------------

ALTER TABLE public.learning_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_paths FORCE ROW LEVEL SECURITY;
CREATE POLICY learning_paths_select_published_or_staff ON public.learning_paths
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY learning_paths_staff_write ON public.learning_paths
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modules FORCE ROW LEVEL SECURITY;
CREATE POLICY modules_select_published_or_staff ON public.modules
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY modules_staff_write ON public.modules
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.lessons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lessons FORCE ROW LEVEL SECURITY;
CREATE POLICY lessons_select_published_or_staff ON public.lessons
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY lessons_staff_write ON public.lessons
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.lesson_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_skills FORCE ROW LEVEL SECURITY;
CREATE POLICY lesson_skills_select_all ON public.lesson_skills FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY lesson_skills_staff_write ON public.lesson_skills
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- Self-reported reading progress: low-stakes, does not by itself grant any
-- skill evidence (see docs/adr/0003), so the owner may write it directly.
ALTER TABLE public.lesson_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lesson_progress FORCE ROW LEVEL SECURITY;
CREATE POLICY lesson_progress_own ON public.lesson_progress
  FOR ALL TO authenticated USING (user_id = auth.uid() OR public.is_staff())
  WITH CHECK (user_id = auth.uid());

-- ---- Quizzes ----------------------------------------------------------------

ALTER TABLE public.quizzes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quizzes FORCE ROW LEVEL SECURITY;
CREATE POLICY quizzes_select_published_or_staff ON public.quizzes
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY quizzes_staff_write ON public.quizzes
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.quiz_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_skills FORCE ROW LEVEL SECURITY;
CREATE POLICY quiz_skills_select_all ON public.quiz_skills FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY quiz_skills_staff_write ON public.quiz_skills
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- quiz_questions / quiz_choices: staff-only, ever. Everyone else reads
-- public.quiz_questions_for_attempt instead (defined in the content model
-- migration), which the view owner (postgres) can populate regardless of
-- these policies.
ALTER TABLE public.quiz_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_questions FORCE ROW LEVEL SECURITY;
CREATE POLICY quiz_questions_staff_only ON public.quiz_questions
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.quiz_choices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_choices FORCE ROW LEVEL SECURITY;
CREATE POLICY quiz_choices_staff_only ON public.quiz_choices
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

GRANT SELECT ON public.quiz_questions_for_attempt TO anon, authenticated;

ALTER TABLE public.quiz_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quiz_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY quiz_attempts_select_own_or_staff ON public.quiz_attempts
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff());
-- No INSERT/UPDATE/DELETE policy: writes only via submit_quiz_attempt().

-- ---- Labs ---------------------------------------------------------------

ALTER TABLE public.labs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.labs FORCE ROW LEVEL SECURITY;
CREATE POLICY labs_select_published_or_staff ON public.labs
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY labs_staff_write ON public.labs
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.lab_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_skills FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_skills_select_all ON public.lab_skills FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY lab_skills_staff_write ON public.lab_skills
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.lab_prerequisites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_prerequisites FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_prerequisites_select_all ON public.lab_prerequisites FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY lab_prerequisites_staff_write ON public.lab_prerequisites
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- Hints: content is only visible once the *specific user* has unlocked that
-- specific hint for a lab instance they own (or they are staff). This is a
-- genuinely row-varying policy, not a blanket published/staff check.
ALTER TABLE public.lab_hints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_hints FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_hints_select_unlocked_or_staff ON public.lab_hints
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.lab_hint_unlocks hu
      JOIN public.lab_instances li ON li.id = hu.lab_instance_id
      WHERE hu.hint_id = lab_hints.id AND li.user_id = auth.uid()
    )
  );
CREATE POLICY lab_hints_staff_write ON public.lab_hints
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- Flags: never selectable by non-staff, even hashed -- verification happens
-- exclusively inside submit_lab_flag().
ALTER TABLE public.lab_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_flags FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_flags_staff_only ON public.lab_flags
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.lab_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_instances FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_instances_select_own_staff_or_instructor ON public.lab_instances
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = lab_instances.user_id
    )
  );
CREATE POLICY lab_instances_insert_own ON public.lab_instances
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY lab_instances_update_own_or_staff ON public.lab_instances
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_staff())
  WITH CHECK (user_id = auth.uid() OR public.is_staff());

ALTER TABLE public.lab_hint_unlocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_hint_unlocks FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_hint_unlocks_select_own_or_staff ON public.lab_hint_unlocks
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR EXISTS (SELECT 1 FROM public.lab_instances li WHERE li.id = lab_hint_unlocks.lab_instance_id AND li.user_id = auth.uid())
  );
-- No INSERT policy: unlocking a hint is a scored action (point_cost) that
-- must go through a grading-adjacent function, not a raw insert.

ALTER TABLE public.lab_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_submissions FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_submissions_select_own_or_staff ON public.lab_submissions
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff());
-- No INSERT policy: writes only via submit_lab_flag().

ALTER TABLE public.lab_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_progress FORCE ROW LEVEL SECURITY;
CREATE POLICY lab_progress_select_own_staff_or_instructor ON public.lab_progress
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_staff()
    OR EXISTS (
      SELECT 1 FROM public.organization_members om_self
      JOIN public.organization_members om_target ON om_target.organization_id = om_self.organization_id
      WHERE om_self.user_id = auth.uid()
        AND om_self.role IN ('instructor', 'team_owner', 'org_admin')
        AND om_target.user_id = lab_progress.user_id
    )
  );
-- No INSERT/UPDATE policy: written only by submit_lab_flag().

-- ---- CTF / Arena ----------------------------------------------------------

ALTER TABLE public.ctf_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ctf_events FORCE ROW LEVEL SECURITY;
CREATE POLICY ctf_events_select_published_or_staff ON public.ctf_events
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY ctf_events_staff_write ON public.ctf_events
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- flag_hash lives on this table. RLS is row-level, not column-level, but
-- that's not actually a problem here: the ONLY policy on this table is
-- "staff can see every column of every row; everyone else sees nothing at
-- all" -- there is no case where a row is visible to a non-staff caller
-- with just one column redacted, so the policy alone is sufficient.
--
-- Note: do NOT additionally REVOKE SELECT from `authenticated` here (an
-- earlier version of this migration did, and it was a real bug -- see
-- SECURITY_AUDIT.md AUDIT-006). Table-level GRANT/REVOKE applies to the
-- Postgres ROLE, and `authenticated` is one shared role for every logged-in
-- user regardless of app-level admin status -- an admin connects as
-- `authenticated` too. Revoking SELECT from `authenticated` blocks admins
-- from ever reading this table (including for CMS management), not just
-- non-staff users; RLS's `is_staff()` check is what must do the filtering.
-- Everyone (including staff) also still has public.ctf_challenges_public
-- for the flag_hash-free published view.
ALTER TABLE public.ctf_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ctf_challenges FORCE ROW LEVEL SECURITY;
CREATE POLICY ctf_challenges_staff_only ON public.ctf_challenges
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

CREATE VIEW public.ctf_challenges_public AS
  SELECT id, event_id, lab_id, slug, title, description, category, difficulty, points, published
  FROM public.ctf_challenges
  WHERE published = true;
GRANT SELECT ON public.ctf_challenges_public TO anon, authenticated;

ALTER TABLE public.ctf_challenge_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ctf_challenge_skills FORCE ROW LEVEL SECURITY;
CREATE POLICY ctf_challenge_skills_select_all ON public.ctf_challenge_skills FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY ctf_challenge_skills_staff_write ON public.ctf_challenge_skills
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.ctf_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ctf_submissions FORCE ROW LEVEL SECURITY;
CREATE POLICY ctf_submissions_select_own_or_staff ON public.ctf_submissions
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff());
-- No INSERT policy: writes only via submit_ctf_flag().

-- ---- Capstones --------------------------------------------------------------

ALTER TABLE public.capstones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.capstones FORCE ROW LEVEL SECURITY;
CREATE POLICY capstones_select_published_or_staff ON public.capstones
  FOR SELECT TO anon, authenticated USING (published OR public.is_staff());
CREATE POLICY capstones_staff_write ON public.capstones
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.capstone_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.capstone_skills FORCE ROW LEVEL SECURITY;
CREATE POLICY capstone_skills_select_all ON public.capstone_skills FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY capstone_skills_staff_write ON public.capstone_skills
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.capstone_labs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.capstone_labs FORCE ROW LEVEL SECURITY;
CREATE POLICY capstone_labs_select_all ON public.capstone_labs FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY capstone_labs_staff_write ON public.capstone_labs
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.capstone_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.capstone_submissions FORCE ROW LEVEL SECURITY;
CREATE POLICY capstone_submissions_select_own_or_staff ON public.capstone_submissions
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff());
CREATE POLICY capstone_submissions_insert_own ON public.capstone_submissions
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND status = 'submitted'
    AND reviewer_id IS NULL
    AND reviewed_at IS NULL
  );
-- Only staff can transition status (review a submission). A user cannot
-- edit their own report or self-mark it passed after submitting.
CREATE POLICY capstone_submissions_update_staff ON public.capstone_submissions
  FOR UPDATE TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());
