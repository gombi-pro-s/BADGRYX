-- ============================================================================
-- labs.has_terminal: a denormalized, non-secret flag so the learner UI can
-- decide whether to offer a terminal launcher WITHOUT ever querying
-- lab_environments directly (which RLS locks to staff-only -- see
-- 20260922000005_lab_terminal.sql and ADR 0009). Whether a lab HAS an
-- authored environment reveals nothing about its content, so it's safe on
-- the broadly-readable `labs` row; kept accurate by a trigger, never
-- hand-maintained by an admin who could forget to toggle it.
-- ============================================================================

ALTER TABLE public.labs ADD COLUMN has_terminal boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.sync_lab_has_terminal()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_lab_id uuid := COALESCE(NEW.lab_id, OLD.lab_id);
BEGIN
  UPDATE public.labs
  SET has_terminal = EXISTS (SELECT 1 FROM public.lab_environments WHERE lab_id = v_lab_id)
  WHERE id = v_lab_id;
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER lab_environments_sync_has_terminal
  AFTER INSERT OR DELETE ON public.lab_environments
  FOR EACH ROW EXECUTE FUNCTION public.sync_lab_has_terminal();
