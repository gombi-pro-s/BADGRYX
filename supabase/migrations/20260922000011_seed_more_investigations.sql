-- ============================================================================
-- Three more real investigations, proving the workspace on distinct
-- scenarios and evidence-correlation patterns beyond the seeded phishing
-- case (20260922000010): a data breach with leaked service-account
-- credentials, a social-engineering pretext built from public OSINT, and
-- malware beaconing to a C2 server. Every artifact set is internally
-- consistent -- timestamps, sizes, and names cross-reference each other,
-- the same discipline as the phishing case.
-- ============================================================================

DO $outer$
DECLARE
  v_investigation_id uuid;
  v_forensics_skill_id uuid;
  v_incident_skill_id uuid;
  v_evidence_skill_id uuid;
  v_osint_skill_id uuid;
  v_auth_skill_id uuid;
  v_network_skill_id uuid;
  v_response_skill_id uuid;
  v_q_id uuid;
BEGIN
  SELECT id INTO v_forensics_skill_id FROM public.skills WHERE slug = 'digital-forensics';
  SELECT id INTO v_incident_skill_id FROM public.skills WHERE slug = 'incident-investigation';
  SELECT id INTO v_evidence_skill_id FROM public.skills WHERE slug = 'evidence-handling';
  SELECT id INTO v_osint_skill_id FROM public.skills WHERE slug = 'osint';
  SELECT id INTO v_auth_skill_id FROM public.skills WHERE slug = 'authentication';
  SELECT id INTO v_network_skill_id FROM public.skills WHERE slug = 'network-security';
  SELECT id INTO v_response_skill_id FROM public.skills WHERE slug = 'incident-response';

  -- ==========================================================================
  -- Investigation 2: Data Breach Timeline Reconstruction
  -- ==========================================================================
  INSERT INTO public.investigations (
    slug, title, briefing, category, difficulty, objectives, estimated_minutes, points, passing_score, published
  ) VALUES (
    'data-breach-timeline', 'Data Breach Timeline Reconstruction',
    E'A monitoring tool flagged an unusually large outbound transfer from the customer database '
    'server overnight. Security wants to know exactly what left, when, and how the attacker got '
    'in. Pull together the firewall log, the file metadata on the server, and what the database '
    'team already knows, and reconstruct the timeline.',
    'forensics', 'medium',
    '["Correlate a network transfer with a specific file by size and timestamp", "Recognize an interactive login on a service account as a red flag", "Trace initial access back to a credential leak"]'::jsonb,
    30, 200, 75, true
  )
  RETURNING id INTO v_investigation_id;

  INSERT INTO public.investigation_skills (investigation_id, skill_id) VALUES
    (v_investigation_id, v_forensics_skill_id),
    (v_investigation_id, v_incident_skill_id),
    (v_investigation_id, v_evidence_skill_id);

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'log_excerpt', 'Firewall outbound transfer log',
    E'2026-02-02 23:58:03 UTC  10.2.0.14 -> 198.51.100.9   bytes=14022   proto=https  (routine)\n'
    '2026-02-03 00:12:47 UTC  10.2.0.14 -> 198.51.100.9   bytes=9871    proto=https  (routine)\n'
    '2026-02-03 02:05:19 UTC  10.2.0.14 -> 203.0.113.201  bytes=118     proto=ssh    session_start\n'
    '2026-02-03 02:17:04 UTC  10.2.0.14 -> 203.0.113.201  bytes=4508382013  proto=ssh  flag=LARGE_TRANSFER',
    0
  );

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'file_metadata', 'customer_export_full.zip -- server metadata',
    E'Path: /var/backups/staging/customer_export_full.zip\n'
    'Owner: svc-backup (service account, no interactive shell configured)\n'
    'Created: 2026-02-03 02:10:41 UTC\n'
    'Last modified: 2026-02-03 02:15:58 UTC\n'
    'Size: 4508382013 bytes (4.2 GB)\n'
    'Note: this export job normally only runs on the 1st of the month, not the 3rd.',
    1
  );

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'chat_transcript', '#database-team -- incident thread',
    E'[08:02] dba-lead: monitoring flagged a huge transfer off db-prod-3 overnight, does anyone '
    'recognize this\n'
    '[08:04] dba-lead: it was svc-backup that ran it, but svc-backup does not have an interactive '
    'shell, it should only ever run the scheduled export cron\n'
    '[08:09] security-eng: checking auth log for svc-backup now\n'
    '[08:11] security-eng: found it -- there is an SSH session for svc-backup starting 02:05 UTC '
    'from 203.0.113.201, that is not one of our office or VPN ranges\n'
    '[08:13] security-eng: also, svc-backup password was in that credential-stuffing list that got '
    'posted publicly last month after the vendor-portal leak, we flagged it for rotation but I do '
    'not think it actually got rotated yet',
    2
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the external IP address the data was exfiltrated to?',
    'exact_text', 0, 1, encode(digest(lower(trim('203.0.113.201')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'How did the attacker most likely obtain access to the svc-backup account?', 'multiple_choice', 1, 1)
  RETURNING id INTO v_q_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_q_id, 'Using a password exposed in an earlier, unrelated credential leak that was never rotated', true, 0),
    (v_q_id, 'By exploiting a SQL injection vulnerability in the backup tool', false, 1),
    (v_q_id, 'Through a phishing email sent to the database team', false, 2);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the exact size, in bytes, of the file that was exfiltrated?',
    'exact_text', 2, 1, encode(digest(lower(trim('4508382013')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'Why is an interactive SSH session for svc-backup itself a red flag, independent of the transfer size?', 'multiple_choice', 3, 1)
  RETURNING id INTO v_q_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_q_id, 'svc-backup is a service account with no interactive shell configured -- it should never have a real SSH session at all', true, 0),
    (v_q_id, 'Interactive SSH sessions are always malicious regardless of account type', false, 1),
    (v_q_id, 'It is not actually unusual for backup accounts to log in interactively', false, 2);

  -- ==========================================================================
  -- Investigation 3: Social Engineering Pretext Analysis
  -- ==========================================================================
  INSERT INTO public.investigations (
    slug, title, briefing, category, difficulty, objectives, estimated_minutes, points, passing_score, published
  ) VALUES (
    'social-engineering-pretext', 'Social Engineering Pretext Analysis',
    E'An employee reported a suspicious phone call from someone claiming to be IT Security, '
    'asking for a password reset. The employee grew suspicious partway through and hung up, then '
    'received a follow-up email a few minutes later. Figure out how the caller built a convincing '
    'story, and whether the follow-up email is legitimate.',
    'osint', 'easy',
    '["Identify pretexting as a social-engineering technique", "Trace a specific fabricated detail back to a public information source", "Recognize a spoofed follow-up email used to reinforce a phone pretext"]'::jsonb,
    20, 150, 75, true
  )
  RETURNING id INTO v_investigation_id;

  INSERT INTO public.investigation_skills (investigation_id, skill_id) VALUES
    (v_investigation_id, v_osint_skill_id),
    (v_investigation_id, v_auth_skill_id),
    (v_investigation_id, v_incident_skill_id);

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'chat_transcript', 'Helpdesk call notes (typed live by the employee)',
    E'Caller said his name was "Alex" from IT Security. He said Dana Whitfield (my actual manager) '
    'had flagged my account for a security review and that I needed to reset my password on the '
    'call to avoid getting locked out before end of day. He also mentioned it was a good time to '
    'do it since I was coming up on my work anniversary and IT likes to clean up old accounts '
    'around then. That detail is what made me pause -- it is true, but it is also literally on my '
    'public profile, so I asked for a ticket number and he hung up.',
    0
  );

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'social_media_profile', 'Public profile -- the targeted employee',
    E'Name: J. Rivera\n'
    'Title: Senior Financial Analyst\n'
    'Reports to: Dana Whitfield, Director of Finance\n'
    'About: "5 years at Corp Example this month! Grateful for the team."\n'
    'Visibility: Public (visible to anyone, not just connections)',
    1
  );

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'email_headers', 'Follow-up email -- full headers',
    E'From: "IT Security" <security@corp-example-support.com>\n'
    'To: j.rivera@corp.example\n'
    'Subject: Re: Your Account Security Review\n'
    'Date: Wed, 04 Feb 2026 14:22:10 +0000\n'
    'Return-Path: <no-reply@corp-example-support.com>\n'
    'Received: from mail9.corp-example-support.com (198.51.100.77)\n'
    '  by mx1.corp.example with ESMTP; Wed, 04 Feb 2026 14:22:08 +0000\n'
    'Message-ID: <9f1e2d@corp-example-support.com>\n\n'
    'Body: "As discussed, please confirm your password here to complete the review: '
    'https://corp-example-support.com/confirm"',
    2
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'What social-engineering technique best describes this attack?', 'multiple_choice', 0, 1)
  RETURNING id INTO v_q_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_q_id, 'Pretexting -- fabricating a believable scenario using real, publicly available details to gain trust', true, 0),
    (v_q_id, 'SQL injection against the helpdesk ticketing system', false, 1),
    (v_q_id, 'A brute-force attack against the employee''s VPN password', false, 2);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the name of the manager the caller referenced to sound credible?',
    'exact_text', 1, 1, encode(digest(lower(trim('Dana Whitfield')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'Where did the caller most likely learn the employee''s manager name and work anniversary?', 'multiple_choice', 2, 1)
  RETURNING id INTO v_q_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_q_id, 'The employee''s own public social media profile', true, 0),
    (v_q_id, 'An internal HR database the attacker would need credentials to access', false, 1),
    (v_q_id, 'A prior unrelated data breach of the company', false, 2);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What domain does the follow-up email actually originate from (per Return-Path), as opposed to the company''s real domain?',
    'exact_text', 3, 1, encode(digest(lower(trim('corp-example-support.com')), 'sha256'), 'hex')
  );

  -- ==========================================================================
  -- Investigation 4: Malware Beaconing -- Identify the C2 Server
  -- ==========================================================================
  INSERT INTO public.investigations (
    slug, title, briefing, category, difficulty, objectives, estimated_minutes, points, passing_score, published
  ) VALUES (
    'malware-beaconing-c2', 'Malware Beaconing: Identify the C2 Server',
    E'An endpoint detection tool flagged a workstation making small, suspiciously regular outbound '
    'connections all day. That pattern usually means malware checking in with a command-and-control '
    'server. Find the C2 server, the persistence mechanism keeping the malware alive across reboots, '
    'and confirm what the WHOIS record says about who registered the domain it resolves to.',
    'forensics', 'medium',
    '["Recognize regular-interval network connections as automated beaconing rather than normal traffic", "Identify a persistence mechanism (autorun/startup entry)", "Correlate an IP address with its WHOIS-registered domain"]'::jsonb,
    30, 200, 75, true
  )
  RETURNING id INTO v_investigation_id;

  INSERT INTO public.investigation_skills (investigation_id, skill_id) VALUES
    (v_investigation_id, v_network_skill_id),
    (v_investigation_id, v_response_skill_id),
    (v_investigation_id, v_forensics_skill_id);

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'network_capture_summary', 'Endpoint connection summary -- WKSTN-0447',
    E'10:00:03  WKSTN-0447 -> 185.220.101.42:8443  bytes=412   TLS\n'
    '10:01:04  WKSTN-0447 -> 185.220.101.42:8443  bytes=398   TLS\n'
    '10:02:03  WKSTN-0447 -> 185.220.101.42:8443  bytes=405   TLS\n'
    '10:03:04  WKSTN-0447 -> 185.220.101.42:8443  bytes=411   TLS\n'
    'Pattern repeats every ~60 seconds, 24 hours a day, including outside business hours.\n'
    'No other host on the network contacts 185.220.101.42.',
    0
  );

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'file_metadata', 'Startup folder entry -- WKSTN-0447',
    E'Path: C:\\Users\\d.chen\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\svchost_update.exe\n'
    'Created: 2026-01-28 09:14:02\n'
    'Digitally signed: No\n'
    'Note: not a real Windows system file despite the name -- genuine svchost.exe never lives in a '
    'user Startup folder.',
    1
  );

  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'whois_record', 'WHOIS: reverse lookup domain for 185.220.101.42',
    E'Domain Name: SYS-UPDATE-CDN.NET\n'
    'Registrar: QuickReg Domains Inc.\n'
    'Creation Date: 2026-01-25T11:03:44Z\n'
    'Registrant Organization: REDACTED FOR PRIVACY\n'
    'Name Server: NS1.PRIVACYGUARD-DNS.NET',
    2
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the IP address the infected workstation is beaconing to?',
    'exact_text', 0, 1, encode(digest(lower(trim('185.220.101.42')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'What does the ~60 second, round-the-clock connection interval most likely indicate?', 'multiple_choice', 1, 1)
  RETURNING id INTO v_q_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_q_id, 'Automated malware beaconing to a command-and-control server', true, 0),
    (v_q_id, 'Normal browser background sync traffic', false, 1),
    (v_q_id, 'A misconfigured printer driver retrying a connection', false, 2);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the filename of the persistence mechanism found in the Startup folder?',
    'exact_text', 2, 1, encode(digest(lower(trim('svchost_update.exe')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'Why does placing this file in the Startup folder matter to the attacker?', 'multiple_choice', 3, 1)
  RETURNING id INTO v_q_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_q_id, 'It ensures the malware automatically relaunches every time the machine reboots (persistence)', true, 0),
    (v_q_id, 'It has no real effect and is just a decoy', false, 1),
    (v_q_id, 'It is required for the file to have a valid digital signature', false, 2);
END $outer$;
