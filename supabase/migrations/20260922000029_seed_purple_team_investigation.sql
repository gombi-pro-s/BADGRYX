-- ============================================================================
-- One real Purple Team pairing: this investigation is the blue-team side of
-- the exact same incident "Cyber Range: Lateral Movement to the Database
-- Host" (cyber-range-lateral-movement-db, 20260922000027) is the red-team
-- side of. The evidence here -- the recovered cron config and the db-prod01
-- auth log -- describes the identical attack a learner (or someone else)
-- carried out in that lab: the same leaked credential, the same source
-- host, the same target. Linked via investigation_labs (20260922000028).
-- ============================================================================

DO $outer$
DECLARE
  v_investigation_id uuid;
  v_incident_skill_id uuid;
  v_forensics_skill_id uuid;
  v_secrets_skill_id uuid;
  v_lab_id uuid;
  v_mc1_id uuid;
  v_mc2_id uuid;
BEGIN
  SELECT id INTO v_incident_skill_id FROM public.skills WHERE slug = 'incident-investigation';
  SELECT id INTO v_forensics_skill_id FROM public.skills WHERE slug = 'digital-forensics';
  SELECT id INTO v_secrets_skill_id FROM public.skills WHERE slug = 'secrets-management';
  SELECT id INTO v_lab_id FROM public.labs WHERE slug = 'cyber-range-lateral-movement-db';

  INSERT INTO public.investigations (
    slug, title, briefing, category, difficulty, objectives, estimated_minutes, points, passing_score, published
  ) VALUES (
    'purple-team-db-lateral-movement', 'Purple Team: Detecting the Database Lateral Movement',
    E'Your SIEM flagged an unusual successful login to the database host, db-prod01. Ops pulled two '
    'things for you: the auth log from db-prod01 itself, and a cron config recovered from the '
    'adjacent web application host, web-app03. Work out how the attacker actually got in, whether '
    'it lines up with anything legitimate, and what should change so it does not happen again. '
    '(This is the blue-team side of the exact same incident a red-team exercise on this platform '
    'walks through step by step -- see the linked lab below if you want to see how the attacker '
    'actually did it.)',
    'forensics', 'medium',
    '["Correlate a login event against a known legitimate schedule to recognize an anomaly", "Identify a plaintext credential in a config file as the actual root cause of an intrusion", "Distinguish a scheduled/automated action from a human-driven one using only log timing", "Recommend remediation that addresses the root cause, not just the symptom"]'::jsonb,
    30, 200, 75, true
  )
  RETURNING id INTO v_investigation_id;

  INSERT INTO public.investigation_skills (investigation_id, skill_id) VALUES
    (v_investigation_id, v_incident_skill_id),
    (v_investigation_id, v_forensics_skill_id),
    (v_investigation_id, v_secrets_skill_id);

  IF v_lab_id IS NOT NULL THEN
    INSERT INTO public.investigation_labs (investigation_id, lab_id) VALUES (v_investigation_id, v_lab_id);
  END IF;

  -- ---- Artifact 1: the recovered cron config (the actual root cause) --------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'document_excerpt', 'Recovered from web-app03: /etc/cron.d/db-backup.conf',
    E'# nightly backup job -- do not edit, managed by ops\n'
    '# target: db-prod01\n'
    '0 2 * * * appuser /usr/local/bin/backup-db.sh --host=db-prod01 --user=dbadmin --password=Tr0pic4l-Storm-91\n',
    0
  );

  -- ---- Artifact 2: db-prod01's own auth log -----------------------------------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'log_excerpt', 'db-prod01 auth log',
    E'2026-02-04 02:00:03 UTC  db-prod01  sshd  LOGIN_SUCCESS  user=dbadmin  src=10.0.2.7 (web-app03, scheduled backup window)\n'
    '2026-02-04 02:00:41 UTC  db-prod01  sshd  LOGOUT  user=dbadmin\n'
    '2026-02-05 02:00:02 UTC  db-prod01  sshd  LOGIN_SUCCESS  user=dbadmin  src=10.0.2.7 (web-app03, scheduled backup window)\n'
    '2026-02-05 02:00:39 UTC  db-prod01  sshd  LOGOUT  user=dbadmin\n'
    '2026-02-05 14:47:22 UTC  db-prod01  sshd  LOGIN_SUCCESS  user=dbadmin  src=10.0.2.7 (web-app03, outside the scheduled window)\n'
    '2026-02-05 14:52:08 UTC  db-prod01  sshd  ACCESS  resource=/home/dbadmin/notes.txt\n'
    '2026-02-05 14:52:51 UTC  db-prod01  sshd  LOGOUT  user=dbadmin\n',
    1
  );

  -- ---- Artifact 3: SOC/ops discussion -----------------------------------------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'chat_transcript', 'SOC -- #incident-triage',
    E'[14:55] siem-bot: ALERT -- successful ssh login to db-prod01 as dbadmin outside the known backup schedule (02:00 UTC daily)\n'
    '[14:57] soc-analyst: source is 10.0.2.7, that''s web-app03. same host that runs the nightly backup job, just at the wrong time\n'
    '[14:58] soc-analyst: pulling the backup script''s config to see what it actually authenticates with\n'
    '[15:02] soc-analyst: it is a plaintext password baked directly into the cron entry. anyone with read access on web-app03 has had this the whole time\n'
    '[15:03] ops-lead: how long has that credential been unrotated?\n'
    '[15:04] soc-analyst: dbadmin''s own notes on db-prod01 say two years',
    2
  );

  -- ---- Questions --------------------------------------------------------------

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'What actually allowed this login to happen?', 'multiple_choice', 0, 1)
  RETURNING id INTO v_mc1_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_mc1_id, 'A real, working credential in plaintext in a world-readable cron config on another host', true, 0),
    (v_mc1_id, 'A brute-force attack against db-prod01''s ssh service', false, 1),
    (v_mc1_id, 'A vulnerability in the ssh daemon itself', false, 2),
    (v_mc1_id, 'Nothing unusual -- this is exactly the scheduled backup job', false, 3);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What hour (UTC, two digits, e.g. "02") does the legitimate scheduled backup actually run at, per the cron config?',
    'exact_text', 1, 1, encode(digest(lower(trim('02')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (
    v_investigation_id,
    'One of the three logins in the auth log does not match the legitimate schedule. What does that mismatch tell you?',
    'multiple_choice', 2, 1
  )
  RETURNING id INTO v_mc2_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_mc2_id, 'Someone (or something) used the same real credential outside of cron''s own schedule -- a human-driven login, not the automated job', true, 0),
    (v_mc2_id, 'Cron jobs commonly run a few hours late, this is normal', false, 1),
    (v_mc2_id, 'The timestamp is a logging error and should be ignored', false, 2);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (
    v_investigation_id,
    'What is the correct remediation here -- the fix that addresses the actual root cause, not just this one login?',
    'multiple_choice', 3, 1
  );
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index)
  SELECT id, v.choice_text, v.is_correct, v.order_index
  FROM public.investigation_questions,
    (VALUES
      ('Rotate the credential and move it out of the cron file into a real secrets manager the backup script reads at runtime', true, 0),
      ('Block 10.0.2.7 at the firewall -- it is a legitimate host, so no further action is needed on the credential itself', false, 1),
      ('Nothing -- dbadmin is an authorized account and the login succeeded normally', false, 2)
    ) AS v(choice_text, is_correct, order_index)
  WHERE investigation_id = v_investigation_id
    AND question_text = 'What is the correct remediation here -- the fix that addresses the actual root cause, not just this one login?';
END $outer$;
