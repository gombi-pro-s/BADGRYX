-- ============================================================================
-- CTF event leaderboard: ctf_events/ctf_challenges/ctf_submissions have
-- existed since the original content model (20260921000008), but nothing
-- has ever aggregated across users to rank them -- RELEASE_CHECKLIST's
-- "Arena/mission UI (CTF timers/leaderboard)" gap.
--
-- ctf_submissions' own RLS (ctf_submissions_select_own_or_staff) is
-- owner-only by design: a learner's per-challenge submission history is
-- theirs. A leaderboard is a different, narrower thing -- a cross-user
-- AGGREGATE (total score, solve count, last-solve time), never which
-- specific challenges a given rival solved or when. Exposing that
-- narrower aggregate needs a SECURITY DEFINER function that deliberately
-- bypasses ctf_submissions' row-level ownership, the same reasoning as
-- every other "one function is the only way to see/do X across users"
-- decision in this schema (grant_platform_role(), admin_search_users()).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ctf_event_leaderboard(p_event_id uuid)
  RETURNS TABLE (
    user_id uuid,
    display_name text,
    total_points integer,
    solved_count integer,
    last_solve_at timestamptz
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- A draft (unpublished) event's leaderboard is staff-only, mirroring
  -- ctf_events_select_published_or_staff on the event row itself -- an
  -- event being unpublished shouldn't be readable through a side door.
  IF NOT EXISTS (
    SELECT 1 FROM public.ctf_events e
    WHERE e.id = p_event_id AND (e.published OR public.is_staff())
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.user_id,
    coalesce(p.display_name, p.username, 'Anonymous')::text AS display_name,
    sum(s.points_awarded)::integer AS total_points,
    count(*)::integer AS solved_count,
    max(s.submitted_at) AS last_solve_at
  FROM public.ctf_submissions s
  JOIN public.ctf_challenges c ON c.id = s.challenge_id
  LEFT JOIN public.profiles p ON p.id = s.user_id
  WHERE c.event_id = p_event_id AND s.correct = true
  GROUP BY s.user_id, p.display_name, p.username
  -- Standard CTF ranking: highest total score first; a tie goes to
  -- whoever reached that score earliest (their last correct submission's
  -- timestamp is the earliest among tied competitors).
  ORDER BY total_points DESC, last_solve_at ASC
  LIMIT 100;
END;
$$;

REVOKE ALL ON FUNCTION public.ctf_event_leaderboard FROM public;
GRANT EXECUTE ON FUNCTION public.ctf_event_leaderboard TO authenticated;
