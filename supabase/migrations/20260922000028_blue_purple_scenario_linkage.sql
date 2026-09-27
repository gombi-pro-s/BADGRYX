-- ============================================================================
-- Blue/Purple Team scenario linkage: cross-reference an investigation (the
-- blue-team side -- evidence to analyze/detect) with the lab(s)/CTF
-- challenge(s) (the red-team side -- the attack that produced that
-- evidence) it's paired with. Mirrors capstone_labs/capstone_skills'
-- exact junction-table shape: a plain many-to-many, publicly readable
-- (nothing sensitive lives in the link itself), staff-write only.
-- ============================================================================

CREATE TABLE public.investigation_labs (
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  PRIMARY KEY (investigation_id, lab_id)
);
COMMENT ON TABLE public.investigation_labs IS
  'Links a blue-team investigation to the red-team lab(s) whose attack it asks the learner to detect/analyze -- Purple Team scenario pairing.';

CREATE TABLE public.investigation_ctf_challenges (
  investigation_id uuid NOT NULL REFERENCES public.investigations (id) ON DELETE CASCADE,
  challenge_id uuid NOT NULL REFERENCES public.ctf_challenges (id) ON DELETE CASCADE,
  PRIMARY KEY (investigation_id, challenge_id)
);
COMMENT ON TABLE public.investigation_ctf_challenges IS
  'Links a blue-team investigation to the red-team CTF challenge(s) whose attack it asks the learner to detect/analyze -- Purple Team scenario pairing.';

ALTER TABLE public.investigation_labs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_labs FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_labs_select_all ON public.investigation_labs FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY investigation_labs_staff_write ON public.investigation_labs
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.investigation_ctf_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investigation_ctf_challenges FORCE ROW LEVEL SECURITY;
CREATE POLICY investigation_ctf_challenges_select_all ON public.investigation_ctf_challenges FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY investigation_ctf_challenges_staff_write ON public.investigation_ctf_challenges
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());
