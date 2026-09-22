-- ============================================================================
-- Proves the seeded "Phishing Campaign: The Fake Invoice" investigation
-- (20260922000010) is not just present but actually completable end-to-end:
-- answering with the real correct answers (matching the actual evidence
-- text) passes, and the osint/digital-forensics/incident-investigation
-- skills genuinely reach DEMONSTRATED via the real grading RPC.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES ('11111111-1111-1111-1111-111111111111', 'alice@test.local');

-- ---- Look up seeded content IDs as postgres (superuser bypasses RLS) ------
-- Mirrors 005_seeded_content_e2e.sql: a real learner reads questions via
-- investigation_questions_for_attempt (RLS-safe); the actual GRADING call
-- below still runs as alice through her real RLS-respecting session.
CREATE TEMP TABLE test_ids AS
SELECT (SELECT id FROM public.investigations WHERE slug = 'phishing-fake-invoice') AS investigation_id;

ALTER TABLE test_ids
  ADD COLUMN osint_skill_id uuid, ADD COLUMN forensics_skill_id uuid, ADD COLUMN incident_skill_id uuid,
  ADD COLUMN mc1_id uuid, ADD COLUMN mc1_correct uuid,
  ADD COLUMN text1_id uuid, ADD COLUMN text2_id uuid,
  ADD COLUMN mc2_id uuid, ADD COLUMN mc2_correct uuid,
  ADD COLUMN mc3_id uuid, ADD COLUMN mc3_correct uuid;

UPDATE test_ids SET
  osint_skill_id = (SELECT id FROM public.skills WHERE slug = 'osint'),
  forensics_skill_id = (SELECT id FROM public.skills WHERE slug = 'digital-forensics'),
  incident_skill_id = (SELECT id FROM public.skills WHERE slug = 'incident-investigation');

UPDATE test_ids SET mc1_id = (
  SELECT id FROM public.investigation_questions
  WHERE investigation_id = test_ids.investigation_id AND question_text = 'What technique does this attack primarily rely on?'
);
UPDATE test_ids SET mc1_correct = (SELECT id FROM public.investigation_choices WHERE question_id = test_ids.mc1_id AND is_correct = true);

UPDATE test_ids SET text1_id = (
  SELECT id FROM public.investigation_questions
  WHERE investigation_id = test_ids.investigation_id
    AND question_text = 'What is the domain used in the phishing link, exactly as it appears in the WHOIS record?'
);
UPDATE test_ids SET text2_id = (
  SELECT id FROM public.investigation_questions
  WHERE investigation_id = test_ids.investigation_id
    AND question_text = 'What source IP address actually used j.rivera''s VPN credentials to log in (per the login log)?'
);

UPDATE test_ids SET mc2_id = (
  SELECT id FROM public.investigation_questions
  WHERE investigation_id = test_ids.investigation_id
    AND question_text LIKE 'The WHOIS creation date is%'
);
UPDATE test_ids SET mc2_correct = (SELECT id FROM public.investigation_choices WHERE question_id = test_ids.mc2_id AND is_correct = true);

UPDATE test_ids SET mc3_id = (
  SELECT id FROM public.investigation_questions
  WHERE investigation_id = test_ids.investigation_id
    AND question_text LIKE 'Based on the timeline, did the attacker%'
);
UPDATE test_ids SET mc3_correct = (SELECT id FROM public.investigation_choices WHERE question_id = test_ids.mc3_id AND is_correct = true);

GRANT SELECT ON test_ids TO authenticated;

DO $$
DECLARE v_missing int;
BEGIN
  SELECT count(*) INTO v_missing FROM test_ids
    WHERE investigation_id IS NULL OR osint_skill_id IS NULL OR forensics_skill_id IS NULL OR incident_skill_id IS NULL
       OR mc1_id IS NULL OR mc1_correct IS NULL OR text1_id IS NULL OR text2_id IS NULL
       OR mc2_id IS NULL OR mc2_correct IS NULL OR mc3_id IS NULL OR mc3_correct IS NULL;
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'FAIL: seeded investigation content is missing pieces (% NULL lookups) -- did the seed migration or this test drift?', v_missing;
  END IF;
  RAISE NOTICE 'PASS: seeded phishing investigation exists (4 artifacts, 5 questions with real answer keys)';
END $$;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

-- ============================================================================
-- 1. Answering with the real correct answers -- including exact_text
--    answers with different case/whitespace than how they're stored,
--    proving normalization works on genuinely realistic input -- passes
--    with a perfect score, and every linked skill reaches DEMONSTRATED.
-- ============================================================================
DO $$
DECLARE
  v_ids record;
  v_submission public.investigation_submissions;
  v_osint_state public.skill_state;
  v_forensics_state public.skill_state;
  v_incident_state public.skill_state;
BEGIN
  SELECT * INTO v_ids FROM test_ids;

  SELECT * INTO v_submission FROM public.submit_investigation_answers(
    v_ids.investigation_id,
    jsonb_build_object(
      v_ids.mc1_id::text, jsonb_build_array(v_ids.mc1_correct),
      v_ids.text1_id::text, '  Invoice-Billing-Support.COM  ', -- realistic messy capitalization/whitespace
      v_ids.text2_id::text, '198.51.100.44',
      v_ids.mc2_id::text, jsonb_build_array(v_ids.mc2_correct),
      v_ids.mc3_id::text, jsonb_build_array(v_ids.mc3_correct)
    )
  );

  IF v_submission.passed IS NOT true THEN RAISE EXCEPTION 'FAIL: expected the submission to pass, score=%', v_submission.score; END IF;
  IF v_submission.score <> 100 THEN RAISE EXCEPTION 'FAIL: expected a perfect score, got %', v_submission.score; END IF;

  SELECT state INTO v_osint_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.osint_skill_id;
  SELECT state INTO v_forensics_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.forensics_skill_id;
  SELECT state INTO v_incident_state FROM public.user_skill_states WHERE user_id = '11111111-1111-1111-1111-111111111111' AND skill_id = v_ids.incident_skill_id;

  IF v_osint_state <> 'DEMONSTRATED' THEN RAISE EXCEPTION 'FAIL: osint skill expected DEMONSTRATED, got %', v_osint_state; END IF;
  IF v_forensics_state <> 'DEMONSTRATED' THEN RAISE EXCEPTION 'FAIL: digital-forensics skill expected DEMONSTRATED, got %', v_forensics_state; END IF;
  IF v_incident_state <> 'DEMONSTRATED' THEN RAISE EXCEPTION 'FAIL: incident-investigation skill expected DEMONSTRATED, got %', v_incident_state; END IF;

  RAISE NOTICE 'PASS: the real seeded investigation is genuinely solvable end-to-end -- perfect score, all 3 linked skills reach DEMONSTRATED';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);
DROP TABLE test_ids;

ROLLBACK;

\echo 'ALL SEEDED INVESTIGATION END-TO-END TESTS PASSED'
