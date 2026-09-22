-- ============================================================================
-- Lab terminal simulator (section 15/16): a real, deterministic virtual
-- environment per lab (filesystem tree + hostname + users), interpreted by
-- a command engine that lives entirely in application code (lib/terminal/),
-- not in this database. This migration only does two things: (1) gives the
-- environment its own securely-locked-down table, separate from `labs`
-- itself, and (2) gives every command a real, append-only transcript.
--
-- Critical design decision (see docs/adr/0009-lab-terminal-server-side.md):
-- `labs.environment_spec` (added in 20260921000008_content_model.sql as a
-- placeholder, never used) is dropped here and replaced by
-- `lab_environments`, a table RLS locks down exactly like `lab_flags` --
-- never selectable by a non-staff session, ever. That's deliberate: the
-- environment's filesystem tree contains the lab's flag content (e.g. the
-- text of a file a user has to `cat`), so it must never reach the browser
-- as raw JSON the way `labs.title`/`labs.description` do -- only the
-- resulting output of a *specific, already-authorized* command may cross
-- that boundary, computed server-side.
-- ============================================================================

ALTER TABLE public.labs DROP COLUMN environment_spec;

CREATE TABLE public.lab_environments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  variant_seed integer NOT NULL DEFAULT 0,
  spec jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (lab_id, variant_seed),
  CONSTRAINT lab_environments_spec_is_object CHECK (jsonb_typeof(spec) = 'object')
);

CREATE TRIGGER lab_environments_set_updated_at
  BEFORE UPDATE ON public.lab_environments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE public.lab_environments IS
  'The authored virtual filesystem/hostname/users for a lab (see '
  'lib/terminal/spec.ts for the exact shape). Never selectable by a '
  'non-staff session -- see the RLS policy below and ADR 0009. Interpreted '
  'exclusively server-side by lib/terminal/execute.ts using a service-role '
  'client whose caller has already independently verified the requesting '
  'user owns a running lab_instance for this lab.';

ALTER TABLE public.lab_environments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_environments FORCE ROW LEVEL SECURITY;

CREATE POLICY lab_environments_staff_only ON public.lab_environments
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- ----------------------------------------------------------------------------
-- lab_terminal_commands: an append-only transcript of every command run in
-- a lab instance's terminal, real input/output (not a canned script). Not
-- a grading input by itself -- a user still has to separately call
-- submit_lab_flag() with whatever flag text they found -- so, unlike
-- lab_flags/scan_findings, this is safe to let the owner insert directly
-- through their own session (same trust level as mentor_messages: a
-- transcript with no grading consequence to its own existence).
-- ----------------------------------------------------------------------------

CREATE TABLE public.lab_terminal_commands (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  lab_instance_id uuid NOT NULL REFERENCES public.lab_instances (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  command text NOT NULL,
  output text NOT NULL,
  cwd_before text NOT NULL,
  cwd_after text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lab_terminal_commands_command_bounded CHECK (char_length(command) <= 2000),
  CONSTRAINT lab_terminal_commands_output_bounded CHECK (char_length(output) <= 8000)
);

CREATE INDEX lab_terminal_commands_instance_idx ON public.lab_terminal_commands (lab_instance_id, created_at);
CREATE INDEX lab_terminal_commands_user_id_idx ON public.lab_terminal_commands (user_id, created_at);

ALTER TABLE public.lab_terminal_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_terminal_commands FORCE ROW LEVEL SECURITY;

CREATE POLICY lab_terminal_commands_select_own_or_staff ON public.lab_terminal_commands
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

CREATE POLICY lab_terminal_commands_insert_own ON public.lab_terminal_commands
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.lab_instances li
      WHERE li.id = lab_instance_id AND li.user_id = auth.uid()
    )
  );

-- No UPDATE/DELETE policy: a transcript, once written, is not editable --
-- same reasoning as mentor_messages.
