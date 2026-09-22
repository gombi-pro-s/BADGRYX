-- ============================================================================
-- Seed one real exam-flagged quiz, proving the "Exam mode" content type
-- (quizzes.is_exam/time_limit_minutes/hint_policy, added in
-- 20260921000008_content_model.sql) is actually reachable and solvable --
-- not just schema-valid. Unlike the lesson-embedded comprehension-check
-- quiz seeded in 20260921000014_seed_sample_content.sql, this quiz has no
-- lesson_id: a standalone timed assessment, tied to the same real
-- 'sql-injection' skill, reachable only through the dedicated /exams flow.
-- ============================================================================

DO $outer$
DECLARE
  v_skill_id uuid;
  v_quiz_id uuid;
  v_question_id uuid;
BEGIN
  SELECT id INTO v_skill_id FROM public.skills WHERE slug = 'sql-injection';

  INSERT INTO public.quizzes (
    slug, title, passing_score, max_attempts, is_exam, time_limit_minutes, hint_policy, published
  ) VALUES (
    'sql-injection-practical-assessment', 'SQL Injection: Practical Assessment',
    80, 2, true, 15, 'none', true
  )
  RETURNING id INTO v_quiz_id;

  INSERT INTO public.quiz_skills (quiz_id, skill_id) VALUES (v_quiz_id, v_skill_id);

  -- Q1 (single_choice, 1pt)
  INSERT INTO public.quiz_questions (id, quiz_id, question_text, question_type, order_index, points)
  VALUES (gen_random_uuid(), v_quiz_id,
    'Which of the following inputs is most likely to indicate a SQL injection attempt against a login form?',
    'single_choice', 0, 1)
  RETURNING id INTO v_question_id;
  INSERT INTO public.quiz_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_question_id, E'\' OR \'1\'=\'1', true, 0),
    (v_question_id, 'user@example.com', false, 1),
    (v_question_id, 'P@ssw0rd!', false, 2),
    (v_question_id, 'admin123', false, 3);

  -- Q2 (single_choice, 1pt)
  INSERT INTO public.quiz_questions (id, quiz_id, question_text, question_type, order_index, points)
  VALUES (gen_random_uuid(), v_quiz_id,
    'What is the primary reason parameterized queries prevent SQL injection?',
    'single_choice', 1, 1)
  RETURNING id INTO v_question_id;
  INSERT INTO public.quiz_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_question_id, 'They separate the query structure from user-supplied data, so input can never be interpreted as SQL', true, 0),
    (v_question_id, 'They automatically encrypt all user input', false, 1),
    (v_question_id, 'They block any request containing the word SELECT', false, 2),
    (v_question_id, 'They run every query inside an isolated sandbox', false, 3);

  -- Q3 (multi_choice, 2pt -- an exact-set match, no partial credit, same as every other multi-select grading in this app)
  INSERT INTO public.quiz_questions (id, quiz_id, question_text, question_type, order_index, points)
  VALUES (gen_random_uuid(), v_quiz_id,
    'Which of the following are effective, real mitigations against SQL injection? (select all that apply)',
    'multi_choice', 2, 2)
  RETURNING id INTO v_question_id;
  INSERT INTO public.quiz_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_question_id, 'Parameterized queries / prepared statements', true, 0),
    (v_question_id, 'Least-privilege database accounts', true, 1),
    (v_question_id, 'Blocklisting the single-quote character', false, 2),
    (v_question_id, 'Input allow-listing where the expected format is known', true, 3);

  -- Q4 (single_choice, 1pt)
  INSERT INTO public.quiz_questions (id, quiz_id, question_text, question_type, order_index, points)
  VALUES (gen_random_uuid(), v_quiz_id,
    'An application builds a SQL query by concatenating unsanitized user input directly into the query string. What is the real risk?',
    'single_choice', 3, 1)
  RETURNING id INTO v_question_id;
  INSERT INTO public.quiz_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_question_id, 'An attacker can alter the query''s logic to bypass authentication or exfiltrate data', true, 0),
    (v_question_id, 'The application will run measurably slower', false, 1),
    (v_question_id, 'The database rejects malformed queries automatically, so there is no real risk', false, 2),
    (v_question_id, 'Only the database administrator''s account can be affected', false, 3);
END $outer$;
