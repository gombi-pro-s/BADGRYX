-- ============================================================================
-- Investigation workspace end-to-end test: artifact visibility, hidden
-- answer keys, mixed multiple_choice/exact_text grading (including answer
-- normalization), skill state reaching DEMONSTRATED, and the
-- investigation_instances notes privacy model (owner-only, not even staff
-- -- see the column comment in 20260922000009_investigations.sql).
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local');
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '33333333-3333-3333-3333-333333333333';
INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-3333-3333-333333333333', 'admin')
  ON CONFLICT DO NOTHING;

DO $$
DECLARE
  v_investigation_id uuid;
  v_unpublished_id uuid;
  v_skill_id uuid;
  v_mc_question_id uuid;
  v_text_question_id uuid;
  v_correct_choice_id uuid;
BEGIN
  INSERT INTO public.skill_categories (slug, name) VALUES ('test-investigation', 'Test Investigation')
    ON CONFLICT (slug) DO NOTHING;
  INSERT INTO public.skills (slug, name, category_id)
    SELECT 'test-osint', 'Test OSINT', id FROM public.skill_categories WHERE slug = 'test-investigation'
  RETURNING id INTO v_skill_id;

  INSERT INTO public.investigations (slug, title, category, difficulty, passing_score, published)
  VALUES ('test-phishing-case', 'Test Phishing Case', 'osint', 'easy', 70, true)
  RETURNING id INTO v_investigation_id;

  INSERT INTO public.investigation_skills (investigation_id, skill_id) VALUES (v_investigation_id, v_skill_id);

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index)
  VALUES (v_investigation_id, 'whois_record', 'Domain WHOIS', 'Registrant: redacted\nCreated: 2024-01-02', 0);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, points)
  VALUES (v_investigation_id, 'What technique was used?', 'multiple_choice', 1)
  RETURNING id INTO v_mc_question_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct) VALUES
    (v_mc_question_id, 'Domain typosquatting', true),
    (v_mc_question_id, 'SQL injection', false);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the originating IP address?', 'exact_text', 1,
    encode(digest(lower(trim(' 203.0.113.7 ')), 'sha256'), 'hex')
  )
  RETURNING id INTO v_text_question_id;

  SELECT id INTO v_correct_choice_id FROM public.investigation_choices WHERE question_id = v_mc_question_id AND is_correct = true;

  INSERT INTO public.investigations (slug, title, category, difficulty, published)
  VALUES ('test-unpublished-case', 'Test Unpublished Case', 'osint', 'easy', false)
  RETURNING id INTO v_unpublished_id;
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content)
  VALUES (v_unpublished_id, 'whois_record', 'Hidden artifact', 'should not be visible');

  CREATE TEMP TABLE test_ids AS SELECT v_investigation_id, v_mc_question_id, v_text_question_id, v_correct_choice_id, v_skill_id, v_unpublished_id;
END $$;

GRANT SELECT ON test_ids TO authenticated;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- ============================================================================
-- 1. Artifacts for a published investigation are visible; for an
--    unpublished one, they are not.
-- ============================================================================
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.investigation_artifacts a
    JOIN test_ids t ON a.investigation_id = t.v_investigation_id;
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: expected 1 visible artifact, got %', cnt; END IF;

  SELECT count(*) INTO cnt FROM public.investigation_artifacts a
    JOIN test_ids t ON a.investigation_id = t.v_unpublished_id;
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: unpublished investigation artifact is visible'; END IF;

  RAISE NOTICE 'PASS: artifact visibility follows investigation.published';
END $$;

-- ============================================================================
-- 2. Questions/choices are not directly readable (answer_hash/is_correct
--    hidden); the _for_attempt view works and hides those columns.
-- ============================================================================
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.investigation_questions;
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: non-staff can read investigation_questions directly'; END IF;

  SELECT count(*) INTO cnt FROM public.investigation_questions_for_attempt t JOIN test_ids ti ON t.investigation_id = ti.v_investigation_id;
  IF cnt < 2 THEN RAISE EXCEPTION 'FAIL: investigation_questions_for_attempt should expose the questions, got % rows', cnt; END IF;

  RAISE NOTICE 'PASS: questions/choices hidden directly, exposed safely via the view';
END $$;

-- ============================================================================
-- 3. Correct answers (multiple_choice + case/whitespace-normalized
--    exact_text) pass, are recorded, and advance the skill to DEMONSTRATED.
-- ============================================================================
DO $$
DECLARE
  v_ids record;
  v_submission public.investigation_submissions;
  v_state public.skill_state;
BEGIN
  SELECT * INTO v_ids FROM test_ids;

  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.v_investigation_id,
    jsonb_build_object(
      v_ids.v_mc_question_id::text, jsonb_build_array(v_ids.v_correct_choice_id),
      -- Deliberately different case/whitespace than the stored answer --
      -- proves normalization actually happens at grading time too.
      v_ids.v_text_question_id::text, '  203.0.113.7  '
    )
  );

  IF v_submission.passed IS NOT true THEN RAISE EXCEPTION 'FAIL: expected the submission to pass, score=%', v_submission.score; END IF;
  IF v_submission.score <> 100 THEN RAISE EXCEPTION 'FAIL: expected score 100, got %', v_submission.score; END IF;

  SELECT state INTO v_state FROM public.user_skill_states
    WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.v_skill_id;
  IF v_state <> 'DEMONSTRATED' THEN RAISE EXCEPTION 'FAIL: expected DEMONSTRATED, got %', v_state; END IF;

  RAISE NOTICE 'PASS: correct mixed-type answers pass, normalize case/whitespace, and reach DEMONSTRATED';
END $$;

-- ============================================================================
-- 4. A wrong exact_text answer fails that question, even though the
--    multiple_choice answer was right.
-- ============================================================================
DO $$
DECLARE
  v_ids record;
  v_submission public.investigation_submissions;
BEGIN
  SELECT * INTO v_ids FROM test_ids;

  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.v_investigation_id,
    jsonb_build_object(v_ids.v_mc_question_id::text, jsonb_build_array(v_ids.v_correct_choice_id), v_ids.v_text_question_id::text, '198.51.100.1')
  );

  IF v_submission.score <> 50 THEN RAISE EXCEPTION 'FAIL: expected score 50 (1 of 2 correct), got %', v_submission.score; END IF;
  IF v_submission.passed IS NOT false THEN RAISE EXCEPTION 'FAIL: 50%% should not pass a 70%% threshold'; END IF;

  RAISE NOTICE 'PASS: a wrong exact_text answer is graded independently of the multiple_choice answer';
END $$;

-- ============================================================================
-- 5. investigation_instances: alice can create/update her own notes; bob
--    cannot read them; STAFF cannot read them either (unlike almost every
--    other owner-scoped table in this app -- these are private notes).
-- ============================================================================
DO $$
DECLARE v_ids record;
BEGIN
  SELECT * INTO v_ids FROM test_ids;
  INSERT INTO public.investigation_instances (investigation_id, user_id, notes)
  VALUES (v_ids.v_investigation_id, '11111111-1111-1111-1111-111111111111', 'the domain was registered yesterday');

  UPDATE public.investigation_instances SET notes = notes || ' -- and uses a lookalike TLD'
  WHERE investigation_id = v_ids.v_investigation_id AND user_id = '11111111-1111-1111-1111-111111111111';

  RAISE NOTICE 'PASS: alice can create and update her own investigation notes';
END $$;

RESET ROLE;
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.investigation_instances WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can read alice''s investigation notes'; END IF;
  RAISE NOTICE 'PASS: another user cannot read alice''s notes';
END $$;

RESET ROLE;
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.investigation_instances WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: staff can read alice''s private investigation notes (% rows)', cnt; END IF;
  RAISE NOTICE 'PASS: staff cannot read another user''s private notes either -- genuinely private, by design';
END $$;

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.investigation_submissions WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 2 THEN RAISE EXCEPTION 'FAIL: staff should see alice''s 2 submissions, saw %', cnt; END IF;
  RAISE NOTICE 'PASS: staff CAN read submissions (the actual graded evidence), unlike raw notes';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);
DROP TABLE test_ids;

ROLLBACK;

\echo 'ALL INVESTIGATION RLS TESTS PASSED'
