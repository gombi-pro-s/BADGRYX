-- ============================================================================
-- Seed data: one complete, real content path end-to-end (learning path ->
-- module -> lesson -> quiz -> guided lab -> CTF challenge), all tied to the
-- 'sql-injection' skill seeded in 20260921000013. This is real educational
-- content, not placeholder text -- it exists so the platform has something
-- genuine to learn from and prove the full pipeline (lesson -> quiz ->
-- lab -> CTF -> Skill Graph) end-to-end from day one, not an empty CMS.
--
-- The lab/CTF flags below are intentionally simple, published training
-- values (not secrets) -- this is standard practice for a training
-- platform's seed content, analogous to a textbook's example answer key.
-- ============================================================================

DO $outer$
DECLARE
  v_skill_id uuid;
  v_path_id uuid;
  v_module_id uuid;
  v_lesson_id uuid;
  v_quiz_id uuid;
  v_question_id uuid;
  v_lab_id uuid;
  v_challenge_id uuid;
  v_lesson_content text;
BEGIN
  SELECT id INTO v_skill_id FROM public.skills WHERE slug = 'sql-injection';

  v_lesson_content := $md$## What is SQL injection?

SQL injection (SQLi) happens when untrusted input is concatenated directly into a SQL query instead of being passed as data. The database cannot tell the difference between the query the developer intended and the query an attacker constructed -- because, after string concatenation, they are the same query.

## A vulnerable example

A login check built like this is vulnerable:

```sql
SELECT * FROM users
WHERE username = '' || username || ''
  AND password = '' || password || ''
;
```

If an attacker submits `admin'--` as the username, the resulting query becomes:

```sql
SELECT * FROM users WHERE username = 'admin'--' AND password = 'anything';
```

Everything after `--` is a SQL comment. The password check never runs -- the attacker is authenticated as `admin` without knowing the password.

## Why it matters

Depending on the query and database permissions, SQL injection can let an attacker read data they should never see (other users' records, other tenants' data), modify or delete data, bypass authentication entirely, or in some configurations execute commands on the underlying server.

## The real fix

Parameterized queries (prepared statements) are the fix, not "better" input filtering. With a parameterized query, the query structure and the data are sent to the database separately -- there is no string to concatenate, so there is nothing to inject into:

```sql
-- Parameter placeholders, not string concatenation
SELECT * FROM users WHERE username = $1 AND password_hash = $2;
```

Allow-listing, escaping, and "sanitizing" input are weaker, error-prone substitutes -- parameterization removes the vulnerability class entirely rather than trying to filter around it.

## What's next

Take the comprehension check below, then head to the guided lab to find and exploit a real SQL injection vulnerability in a controlled environment, and the CTF challenge to demonstrate it independently.
$md$;

  -- ---- Learning path / module / lesson ---------------------------------
  INSERT INTO public.learning_paths (slug, title, description, published, order_index)
  VALUES (
    'web-application-security-fundamentals',
    'Web Application Security Fundamentals',
    'Core web vulnerability classes, starting with SQL injection: how it happens, how to find it, and how to fix it for good.',
    true, 0
  )
  RETURNING id INTO v_path_id;

  INSERT INTO public.modules (path_id, slug, title, description, published, order_index)
  VALUES (
    v_path_id, 'sql-injection', 'SQL Injection',
    'Understand, identify, and remediate SQL injection vulnerabilities.',
    true, 0
  )
  RETURNING id INTO v_module_id;

  INSERT INTO public.lessons (module_id, slug, title, summary, content_markdown, estimated_minutes, published, order_index)
  VALUES (
    v_module_id,
    'introduction-to-sql-injection',
    'Introduction to SQL Injection',
    'What SQL injection is, why it happens, and what it lets an attacker do.',
    v_lesson_content,
    12, true, 0
  )
  RETURNING id INTO v_lesson_id;

  INSERT INTO public.lesson_skills (lesson_id, skill_id) VALUES (v_lesson_id, v_skill_id);

  -- ---- Comprehension-check quiz -----------------------------------------
  INSERT INTO public.quizzes (lesson_id, slug, title, passing_score, published)
  VALUES (v_lesson_id, 'sql-injection-comprehension-check', 'SQL Injection: Comprehension Check', 70, true)
  RETURNING id INTO v_quiz_id;

  INSERT INTO public.quiz_skills (quiz_id, skill_id) VALUES (v_quiz_id, v_skill_id);

  INSERT INTO public.quiz_questions (id, quiz_id, question_text, order_index, points)
  VALUES (gen_random_uuid(), v_quiz_id, 'Why does SQL injection happen?', 0, 1)
  RETURNING id INTO v_question_id;
  INSERT INTO public.quiz_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_question_id, 'Untrusted input is concatenated directly into a query instead of passed as data', true, 0),
    (v_question_id, 'The database server is running an outdated version', false, 1),
    (v_question_id, 'The website does not use HTTPS', false, 2);

  INSERT INTO public.quiz_questions (id, quiz_id, question_text, order_index, points)
  VALUES (gen_random_uuid(), v_quiz_id, 'What actually fixes SQL injection?', 1, 1)
  RETURNING id INTO v_question_id;
  INSERT INTO public.quiz_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_question_id, 'Parameterized queries / prepared statements', true, 0),
    (v_question_id, 'Blocking the single-quote character', false, 1),
    (v_question_id, 'Rate limiting the login endpoint', false, 2);

  -- ---- Guided lab -----------------------------------------------------------
  INSERT INTO public.labs (
    slug, title, description, category, difficulty, objectives, estimated_minutes, points, published
  ) VALUES (
    'sqli-101', 'SQL Injection 101',
    'A login form checks credentials with a string-concatenated SQL query. Bypass authentication without knowing a valid password, then retrieve the flag from the resulting session.',
    'web', 'easy',
    '["Identify a SQL-injectable input field", "Bypass authentication using a crafted username", "Explain why the fix is parameterized queries, not input filtering"]'::jsonb,
    45, 100, true
  )
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_skills (lab_id, skill_id) VALUES (v_lab_id, v_skill_id);

  INSERT INTO public.lab_hints (lab_id, level, content, point_cost) VALUES
    (v_lab_id, 1, 'The login query is built by concatenating the username field directly into a SQL WHERE clause.', 0),
    (v_lab_id, 2, 'A single quote followed by a SQL comment can terminate the intended query early.', 5),
    (v_lab_id, 3, 'Try a username of admin''-- as the login (with the trailing SQL comment).', 15);

  INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed)
  VALUES (v_lab_id, 'flag', encode(digest('ICOREPEN{sql1_4uth_byp4ss_101}', 'sha256'), 'hex'), 0);

  -- ---- CTF challenge (independent, unguided demonstration) ------------------
  INSERT INTO public.ctf_challenges (
    slug, title, description, category, difficulty, points, flag_hash, published
  ) VALUES (
    'web-sqli-login-bypass', 'Login Bypass',
    'An admin panel''s login form is vulnerable to SQL injection. No hints this time -- find the injection point and bypass authentication on your own.',
    'web', 'easy', 250,
    encode(digest('ICOREPEN{ung41ded_sql1_ftw}', 'sha256'), 'hex'), true
  )
  RETURNING id INTO v_challenge_id;

  INSERT INTO public.ctf_challenge_skills (challenge_id, skill_id) VALUES (v_challenge_id, v_skill_id);
END $outer$;
