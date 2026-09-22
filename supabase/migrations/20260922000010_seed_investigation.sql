-- ============================================================================
-- Seed one complete real investigation end-to-end, the same way
-- 20260921000014_seed_sample_content.sql proved the grading pipeline with a
-- real SQL injection lab: a genuine phishing-campaign scenario (lookalike
-- domain registered days before the attack, spoofed headers, credential
-- theft confirmed in a login log) with internally consistent dates/details
-- across every artifact -- not decoration, but the actual evidence trail a
-- learner has to correlate to answer correctly.
-- ============================================================================

DO $outer$
DECLARE
  v_investigation_id uuid;
  v_osint_skill_id uuid;
  v_forensics_skill_id uuid;
  v_incident_skill_id uuid;
  v_mc1_id uuid;
  v_mc2_id uuid;
BEGIN
  SELECT id INTO v_osint_skill_id FROM public.skills WHERE slug = 'osint';
  SELECT id INTO v_forensics_skill_id FROM public.skills WHERE slug = 'digital-forensics';
  SELECT id INTO v_incident_skill_id FROM public.skills WHERE slug = 'incident-investigation';

  INSERT INTO public.investigations (
    slug, title, briefing, category, difficulty, objectives, estimated_minutes, points, passing_score, published
  ) VALUES (
    'phishing-fake-invoice', 'Phishing Campaign: The Fake Invoice',
    E'An employee reported clicking a link in what looked like an overdue-invoice email, then '
    'entering their VPN credentials on the page it opened. IT pulled the email headers, ran a '
    'WHOIS lookup on the link''s domain, and pulled the VPN login log for the affected account. '
    'Your job: work through the evidence below and reconstruct what actually happened -- was this '
    'really a targeted, prepared attack, or something more opportunistic? And did the attacker '
    'actually get in?',
    'osint', 'medium',
    '["Correlate timestamps across independent evidence sources to build a timeline", "Distinguish a spoofed sender from the mail server that actually delivered a message", "Use a domain''s registration date as evidence of premeditation", "Confirm whether stolen credentials were actually used, not just captured"]'::jsonb,
    35, 200, 75, true
  )
  RETURNING id INTO v_investigation_id;

  INSERT INTO public.investigation_skills (investigation_id, skill_id) VALUES
    (v_investigation_id, v_osint_skill_id),
    (v_investigation_id, v_forensics_skill_id),
    (v_investigation_id, v_incident_skill_id);

  -- ---- Artifact 1: the phishing email's full headers ------------------------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'email_headers', 'Phishing email -- full headers',
    E'From: "Accounts Payable" <billing@corp-finance.example>\n'
    'To: j.rivera@corp.example\n'
    'Subject: Invoice #48213 Overdue -- Action Required\n'
    'Date: Mon, 13 Jan 2026 09:14:02 +0000\n'
    'Return-Path: <no-reply@invoice-billing-support.com>\n'
    'Received: from mail-relay-9.invoice-billing-support.com (198.51.100.44)\n'
    '  by mx1.corp.example with ESMTP id 7f3a2c; Mon, 13 Jan 2026 09:14:00 +0000\n'
    'Received: from [10.0.0.5] (unverified [198.51.100.44])\n'
    '  by mail-relay-9.invoice-billing-support.com; Mon, 13 Jan 2026 09:13:55 +0000\n'
    'Message-ID: <a1b2c3@invoice-billing-support.com>\n'
    'Content-Type: text/html\n\n'
    'Body (rendered): "Your invoice #48213 is 14 days overdue. View and pay now: '
    'https://invoice-billing-support.com/pay?id=48213"',
    0
  );

  -- ---- Artifact 2: WHOIS record for the link's domain ------------------------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'whois_record', 'WHOIS: invoice-billing-support.com',
    E'Domain Name: INVOICE-BILLING-SUPPORT.COM\n'
    'Registry Domain ID: 2847193-COM\n'
    'Registrar: NameHaven Registrar LLC\n'
    'Creation Date: 2026-01-10T03:22:11Z\n'
    'Registry Expiry Date: 2027-01-10T03:22:11Z\n'
    'Registrant Organization: REDACTED FOR PRIVACY\n'
    'Registrant Country: (privacy service)\n'
    'Name Server: NS1.PRIVACYGUARD-DNS.NET\n'
    'Name Server: NS2.PRIVACYGUARD-DNS.NET\n'
    'DNSSEC: unsigned',
    1
  );

  -- ---- Artifact 3: internal IT/Slack-style transcript ------------------------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'chat_transcript', 'IT helpdesk -- #security-incidents',
    E'[09:41] j.rivera: hey I think I messed up, I got an email about an overdue invoice and clicked '
    'the link, it looked exactly like our normal billing portal so I put in my VPN username and '
    'password before I noticed the URL looked off\n'
    '[09:42] j.rivera: the page just said "processing" and then errored out, I did not get to a real '
    'invoice\n'
    '[09:45] it-oncall: thanks for reporting this fast. what time did you enter the credentials, roughly?\n'
    '[09:46] j.rivera: maybe 9:20-9:25am? right after I got the email\n'
    '[09:47] it-oncall: ok, disabling your VPN account now as a precaution and pulling the login log '
    'to check for any use of it before the disable',
    2
  );

  -- ---- Artifact 4: VPN login log ---------------------------------------------
  INSERT INTO public.investigation_artifacts (investigation_id, artifact_type, title, content, order_index) VALUES (
    v_investigation_id, 'log_excerpt', 'VPN login log -- account j.rivera',
    E'2026-01-12 17:03:11 UTC  j.rivera  LOGIN_SUCCESS  src=203.0.113.19  (office NAT, expected)\n'
    '2026-01-12 17:58:40 UTC  j.rivera  LOGOUT\n'
    '2026-01-13 09:29:52 UTC  j.rivera  LOGIN_SUCCESS  src=198.51.100.44  (unrecognized)\n'
    '2026-01-13 09:31:07 UTC  j.rivera  ACCESS  resource=/finance/payroll-export (unusual for this account)\n'
    '2026-01-13 09:47:15 UTC  j.rivera  ACCOUNT_DISABLED  by=it-oncall',
    3
  );

  -- ---- Questions --------------------------------------------------------------

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (v_investigation_id, 'What technique does this attack primarily rely on?', 'multiple_choice', 0, 1)
  RETURNING id INTO v_mc1_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_mc1_id, 'A lookalike/spoofed domain impersonating a trusted sender', true, 0),
    (v_mc1_id, 'SQL injection against the corporate mail server', false, 1),
    (v_mc1_id, 'A brute-force attack against the VPN', false, 2),
    (v_mc1_id, 'An insider deliberately leaking credentials', false, 3);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What is the domain used in the phishing link, exactly as it appears in the WHOIS record?',
    'exact_text', 1, 1, encode(digest(lower(trim('invoice-billing-support.com')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points, answer_hash)
  VALUES (
    v_investigation_id, 'What source IP address actually used j.rivera''s VPN credentials to log in (per the login log)?',
    'exact_text', 2, 1, encode(digest(lower(trim('198.51.100.44')), 'sha256'), 'hex')
  );

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (
    v_investigation_id,
    'The WHOIS creation date is 2026-01-10 and the phishing email was sent 2026-01-13. What does that gap suggest?',
    'multiple_choice', 3, 1
  )
  RETURNING id INTO v_mc2_id;
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index) VALUES
    (v_mc2_id, 'The domain was registered specifically for this campaign, only days beforehand', true, 0),
    (v_mc2_id, 'The domain has been used for years and is unrelated to this incident', false, 1),
    (v_mc2_id, 'The dates are too far apart to be related', false, 2);

  INSERT INTO public.investigation_questions (investigation_id, question_text, question_type, order_index, points)
  VALUES (
    v_investigation_id,
    'Based on the timeline, did the attacker successfully use the stolen credentials before the account was disabled?',
    'multiple_choice', 4, 1
  );
  -- Reuse the just-inserted question for its choices via a lookup, since we
  -- did not capture its id above (only the row insert was needed).
  INSERT INTO public.investigation_choices (question_id, choice_text, is_correct, order_index)
  SELECT id, v.choice_text, v.is_correct, v.order_index
  FROM public.investigation_questions,
    (VALUES
      ('Yes -- there is a successful login from the attacker''s IP using the real account, before it was disabled', true, 0),
      ('No -- the account was disabled before any login occurred', false, 1),
      ('Unclear -- the log does not show which IP logged in', false, 2)
    ) AS v(choice_text, is_correct, order_index)
  WHERE investigation_id = v_investigation_id
    AND question_text = 'Based on the timeline, did the attacker successfully use the stolen credentials before the account was disabled?';
END $outer$;
