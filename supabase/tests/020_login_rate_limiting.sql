-- ============================================================================
-- Proves login rate limiting (20260922000020) is real: the `anon` role (the
-- only role that exists pre-login) can call all three functions; a fresh
-- email is allowed; 5 recorded failures block a 6th attempt with a positive
-- retry_after_seconds; a completely different email is unaffected by
-- another email's failures; clear_login_attempts() (the successful-login
-- path) immediately un-blocks; and attempts older than the 15-minute window
-- no longer count.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================================
-- 1. The `anon` role -- the only role that exists before a session is
--    established -- can call all three functions. This is the one place in
--    the schema that grants EXECUTE to anon at all, so prove it's real.
-- ============================================================================
SET ROLE anon;
DO $$
DECLARE v_row record;
BEGIN
  SELECT * INTO v_row FROM public.check_login_rate_limit('fresh@test.local');
  IF v_row.allowed IS DISTINCT FROM true OR v_row.retry_after_seconds IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FAIL: a fresh email should be allowed with no retry wait, got allowed=% retry=%',
      v_row.allowed, v_row.retry_after_seconds;
  END IF;
  RAISE NOTICE 'PASS: the anon role can call check_login_rate_limit, and a fresh email is allowed';

  PERFORM public.record_failed_login_attempt('fresh@test.local');
  PERFORM public.clear_login_attempts('fresh@test.local');
  RAISE NOTICE 'PASS: the anon role can call record_failed_login_attempt and clear_login_attempts';
END $$;
RESET ROLE;

-- ============================================================================
-- 2. 5 failed attempts block a 6th; a different email is unaffected.
-- ============================================================================
SET ROLE anon;
DO $$
DECLARE v_row record; i int;
BEGIN
  FOR i IN 1..5 LOOP
    PERFORM public.record_failed_login_attempt('victim@test.local');
  END LOOP;

  SELECT * INTO v_row FROM public.check_login_rate_limit('victim@test.local');
  IF v_row.allowed <> false OR v_row.retry_after_seconds <= 0 THEN
    RAISE EXCEPTION 'FAIL: 5 failed attempts should block with a positive retry wait, got allowed=% retry=%',
      v_row.allowed, v_row.retry_after_seconds;
  END IF;
  RAISE NOTICE 'PASS: 5 failed attempts in the window block the 6th attempt (retry_after_seconds=%)', v_row.retry_after_seconds;

  SELECT * INTO v_row FROM public.check_login_rate_limit('bystander@test.local');
  IF v_row.allowed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: an unrelated email should not be blocked by victim@test.local''s failures';
  END IF;
  RAISE NOTICE 'PASS: a different email is completely unaffected by another email''s failed attempts';
END $$;
RESET ROLE;

-- ============================================================================
-- 3. clear_login_attempts() (the real successful-login path) immediately
--    un-blocks, rather than waiting out the window.
-- ============================================================================
SET ROLE anon;
DO $$
DECLARE v_row record;
BEGIN
  PERFORM public.clear_login_attempts('victim@test.local');
  SELECT * INTO v_row FROM public.check_login_rate_limit('victim@test.local');
  IF v_row.allowed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: clear_login_attempts should immediately un-block, got allowed=%', v_row.allowed;
  END IF;
  RAISE NOTICE 'PASS: clear_login_attempts (the successful-login path) immediately un-blocks';
END $$;
RESET ROLE;

-- ============================================================================
-- 4. Attempts older than the 15-minute window no longer count, even if
--    there are 5+ of them.
-- ============================================================================
SET ROLE anon;
DO $$
BEGIN
  PERFORM public.record_failed_login_attempt('stale@test.local');
  PERFORM public.record_failed_login_attempt('stale@test.local');
  PERFORM public.record_failed_login_attempt('stale@test.local');
  PERFORM public.record_failed_login_attempt('stale@test.local');
  PERFORM public.record_failed_login_attempt('stale@test.local');
END $$;
RESET ROLE;

-- Backdate them past the window (superuser fixture write -- RLS on
-- login_attempts has zero policies, so only a superuser/bypassrls role can
-- do this at all, which is itself proof there's no app-facing write path).
UPDATE public.login_attempts SET created_at = now() - interval '20 minutes' WHERE email = 'stale@test.local';

SET ROLE anon;
DO $$
DECLARE v_row record;
BEGIN
  SELECT * INTO v_row FROM public.check_login_rate_limit('stale@test.local');
  IF v_row.allowed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: attempts older than the window should not count, got allowed=%', v_row.allowed;
  END IF;
  RAISE NOTICE 'PASS: failed attempts older than the 15-minute window no longer count';
END $$;
RESET ROLE;

ROLLBACK;

\echo 'ALL LOGIN RATE LIMITING TESTS PASSED'
