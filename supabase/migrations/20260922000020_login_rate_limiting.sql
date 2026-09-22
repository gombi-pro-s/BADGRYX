-- ============================================================================
-- Login rate limiting.
--
-- Until now signInAction() called supabase.auth.signInWithPassword() with no
-- limit at all on repeated attempts -- an attacker could brute-force or
-- credential-stuff any account's password with unlimited, unthrottled
-- requests. This is a real, exploitable gap, not a hypothetical one.
--
-- The three functions below are called from signInAction() itself (server
-- action, runs before any session exists, so the caller is the Postgres
-- `anon` role -- this is the one place in the schema that grants EXECUTE to
-- `anon`, deliberately, because there is no other identity to check against
-- pre-login):
--
--   1. check_login_rate_limit(email) -- called BEFORE signInWithPassword.
--      Blocks if 5+ failed attempts for that email were recorded in the
--      last 15 minutes.
--   2. record_failed_login_attempt(email) -- called after a failed
--      signInWithPassword.
--   3. clear_login_attempts(email) -- called after a successful
--      signInWithPassword, so a legitimate login immediately resets the
--      counter rather than waiting out the window.
--
-- Only FAILED attempts are ever stored, and a success clears them -- the
-- table never grows from normal usage, only from actual failed attempts
-- that haven't yet rolled off the window or been cleared by a success.
--
-- Known, accepted limitation (documented rather than silently ignored, see
-- docs/adr/0014-login-rate-limiting.md): this is keyed by email, not IP,
-- so it cannot distinguish "one attacker hammering many accounts" from
-- "many legitimate users failing their own password" and it means an
-- attacker who knows a victim's email can force that victim's account into
-- a (short, 15-minute) lockout. This is a standard trade-off for
-- application-layer rate limiting without a WAF/edge layer in front of it,
-- and the lockout window is short specifically to bound that cost.
-- ============================================================================

CREATE TABLE public.login_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email citext NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.login_attempts IS
  'Only failed login attempts are stored; a successful login clears all rows '
  'for that email. Never read or written directly -- see check_login_rate_limit()/'
  'record_failed_login_attempt()/clear_login_attempts().';

CREATE INDEX login_attempts_email_created_at_idx ON public.login_attempts (email, created_at);

ALTER TABLE public.login_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_attempts FORCE ROW LEVEL SECURITY;
-- Deliberately no policies at all: nobody, not even an authenticated user
-- reading their own email, can SELECT/INSERT/UPDATE/DELETE this table
-- directly. The three SECURITY DEFINER functions below are the only access
-- path, exactly like organization_invitations.token_hash.

CREATE OR REPLACE FUNCTION public.check_login_rate_limit(p_email citext)
  RETURNS TABLE (allowed boolean, retry_after_seconds integer)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_window CONSTANT interval := interval '15 minutes';
  v_max_attempts CONSTANT int := 5;
  v_count int;
  v_oldest timestamptz;
BEGIN
  SELECT count(*), min(created_at) INTO v_count, v_oldest
    FROM public.login_attempts
    WHERE email = p_email AND created_at > now() - v_window;

  IF v_count >= v_max_attempts THEN
    RETURN QUERY SELECT false, GREATEST(1, ceil(extract(epoch FROM (v_oldest + v_window - now())))::integer);
  ELSE
    RETURN QUERY SELECT true, 0;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_login_rate_limit FROM public;
GRANT EXECUTE ON FUNCTION public.check_login_rate_limit TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_failed_login_attempt(p_email citext)
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.login_attempts (email) VALUES (p_email);
$$;

REVOKE ALL ON FUNCTION public.record_failed_login_attempt FROM public;
GRANT EXECUTE ON FUNCTION public.record_failed_login_attempt TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.clear_login_attempts(p_email citext)
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  DELETE FROM public.login_attempts WHERE email = p_email;
$$;

REVOKE ALL ON FUNCTION public.clear_login_attempts FROM public;
GRANT EXECUTE ON FUNCTION public.clear_login_attempts TO anon, authenticated, service_role;
