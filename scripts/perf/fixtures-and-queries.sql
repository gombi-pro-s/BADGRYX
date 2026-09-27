-- ============================================================================
-- Load/performance fixture generation + EXPLAIN ANALYZE for this app's
-- actual hot, user-scoped queries (dashboard, skills matrix, scanner list),
-- run against a real local Postgres with every real migration and RLS
-- policy applied -- not a separate synthetic schema. Volume is synthetic
-- (necessarily -- this is a load test, not production data), but every row
-- satisfies the same constraints/FKs/RLS a real row would.
--
-- One user ("perfuser1") is deliberately given a much larger personal
-- history than the rest, so the query being measured has to filter a
-- meaningfully large table down via an index, not just skim a small one --
-- the realistic version of "does this stay fast as the platform grows."
-- ============================================================================

\set ON_ERROR_STOP on
\timing on

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ----------------------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------------------

\echo '==> Generating 300 synthetic users (handle_new_user() gives each a profile + baseline role)'
INSERT INTO auth.users (id, email)
SELECT ('00000000-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid,
       'perfuser' || i || '@test.local'
FROM generate_series(1, 300) AS i;

\echo '==> Generating user_skill_states (dense cross join, ~50% of all user x skill pairs)'
INSERT INTO public.user_skill_states (user_id, skill_id, state)
SELECT u.id, s.id,
  (ARRAY['NOT_STARTED','LEARNING','PRACTICING','ASSESSED','DEMONSTRATED','MASTERED']::public.skill_state[])[1 + floor(random() * 6)::int]
FROM auth.users u
CROSS JOIN public.skills s
WHERE u.email LIKE 'perfuser%' AND random() < 0.5
ON CONFLICT DO NOTHING;

\echo '==> Generating skill_evidence (300 rows for perfuser1, 25 each for the rest)'
INSERT INTO public.skill_evidence (user_id, skill_id, evidence_type, outcome, source_type)
SELECT
  u.id,
  (SELECT id FROM public.skills ORDER BY random() LIMIT 1),
  (ARRAY['theory','quiz','guided_lab','unguided_lab','ctf']::public.skill_evidence_type[])[1 + floor(random() * 5)::int],
  (ARRAY['passed','failed','partial']::public.skill_evidence_outcome[])[1 + floor(random() * 3)::int],
  'quiz'
FROM auth.users u, generate_series(1, CASE WHEN u.email = 'perfuser1@test.local' THEN 300 ELSE 25 END) g
WHERE u.email LIKE 'perfuser%';

\echo '==> Generating scans (800 for perfuser1, 5 each for the rest)'
INSERT INTO public.scans (user_id, title, target_type, status, total_files, total_findings, findings_by_severity, completed_at)
SELECT
  u.id, 'Perf scan ' || g, 'pasted_snippet', 'completed', 1, 3, '{"medium": 3}'::jsonb, now() - (g || ' minutes')::interval
FROM auth.users u, generate_series(1, CASE WHEN u.email = 'perfuser1@test.local' THEN 800 ELSE 5 END) g
WHERE u.email LIKE 'perfuser%';

\echo '==> Generating 20 platform-wide announcements'
INSERT INTO public.announcements (title, body_markdown, published, published_at)
SELECT 'Announcement ' || i, 'Body text for announcement ' || i, true, now() - (i || ' hours')::interval
FROM generate_series(1, 20) AS i;

\echo '==> Fixture volume:'
SELECT 'user_skill_states' AS table_name, count(*) FROM public.user_skill_states
UNION ALL SELECT 'skill_evidence', count(*) FROM public.skill_evidence
UNION ALL SELECT 'scans', count(*) FROM public.scans
UNION ALL SELECT 'announcements', count(*) FROM public.announcements;

-- ----------------------------------------------------------------------------
-- Hot queries, run as perfuser1 (the power user) so RLS is genuinely
-- evaluated the same way it would be for a real request.
-- ----------------------------------------------------------------------------

CALL test_act_as('00000000-0000-0000-0000-000000000001');

\echo '=== QUERY dashboard_profile ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT display_name, username FROM public.profiles WHERE id = '00000000-0000-0000-0000-000000000001';

\echo '=== QUERY dashboard_skill_states ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT state FROM public.user_skill_states WHERE user_id = '00000000-0000-0000-0000-000000000001';

\echo '=== QUERY dashboard_subscription ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT plan_id, status FROM public.subscriptions
WHERE subject_type = 'user' AND subject_id = '00000000-0000-0000-0000-000000000001'
  AND status IN ('trialing', 'active', 'past_due');

\echo '=== QUERY dashboard_announcements ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, body_markdown, published_at FROM public.announcements
WHERE published = true AND (expires_at IS NULL OR expires_at > now())
ORDER BY published_at DESC LIMIT 5;

\echo '=== QUERY skills_matrix_skills ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, slug, name, category_id, description FROM public.skills ORDER BY name;

\echo '=== QUERY skills_matrix_user_skill_states ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT skill_id, state FROM public.user_skill_states WHERE user_id = '00000000-0000-0000-0000-000000000001';

\echo '=== QUERY skills_matrix_skill_evidence ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT skill_id, evidence_type, outcome FROM public.skill_evidence WHERE user_id = '00000000-0000-0000-0000-000000000001';

\echo '=== QUERY scanner_scan_list ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, title, status, total_files, total_findings, findings_by_severity, created_at
FROM public.scans WHERE user_id = '00000000-0000-0000-0000-000000000001'
ORDER BY created_at DESC LIMIT 20;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

\echo '==> Done.'
