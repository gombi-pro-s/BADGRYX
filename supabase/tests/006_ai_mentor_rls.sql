-- ============================================================================
-- AI Mentor RLS regression tests: a user's conversations/messages are
-- private to them (plus staff for support), and a user can never insert a
-- message into another user's conversation.
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

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ============================================================================
-- 1. Alice can create her own conversation and post a message to it.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_conv_id uuid;
BEGIN
  INSERT INTO public.mentor_conversations (user_id, context_type, title)
  VALUES ('11111111-1111-1111-1111-111111111111', 'general', 'Question about SQLi')
  RETURNING id INTO v_conv_id;

  INSERT INTO public.mentor_messages (conversation_id, user_id, role, mode, content)
  VALUES (v_conv_id, '11111111-1111-1111-1111-111111111111', 'user', 'explain', 'What is SQL injection?');

  RAISE NOTICE 'PASS: user can create own conversation and post own message';
END $$;

-- ============================================================================
-- 2. Bob cannot see Alice's conversation or messages.
-- ============================================================================
CALL test_act_as('22222222-2222-2222-2222-222222222222');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.mentor_conversations WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s conversations'; END IF;

  SELECT count(*) INTO cnt FROM public.mentor_messages WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 0 THEN RAISE EXCEPTION 'FAIL: bob can see alice''s messages'; END IF;
  RAISE NOTICE 'PASS: another user cannot read alice''s conversations or messages';
END $$;

-- ============================================================================
-- 3. Bob cannot insert a message into Alice's conversation, even claiming
--    his own user_id (the conversation-ownership check in the INSERT policy
--    must catch this, not just the user_id = auth.uid() check).
-- ============================================================================
DO $$
DECLARE v_alice_conv_id uuid;
BEGIN
  RESET ROLE;
  SELECT id INTO v_alice_conv_id FROM public.mentor_conversations WHERE user_id = '11111111-1111-1111-1111-111111111111' LIMIT 1;

  CALL test_act_as('22222222-2222-2222-2222-222222222222');

  BEGIN
    INSERT INTO public.mentor_messages (conversation_id, user_id, role, mode, content)
    VALUES (v_alice_conv_id, '22222222-2222-2222-2222-222222222222', 'user', 'explain', 'injected message');
    RAISE EXCEPTION 'FAIL: bob inserted a message into alice''s conversation';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot insert a message into another user''s conversation (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 4. Bob cannot forge a message claiming to be from alice within a
--    conversation he does own (user_id must match auth.uid(), not just any
--    value the client provides).
-- ============================================================================
DO $$
DECLARE v_bob_conv_id uuid;
BEGIN
  INSERT INTO public.mentor_conversations (user_id, context_type)
  VALUES ('22222222-2222-2222-2222-222222222222', 'general')
  RETURNING id INTO v_bob_conv_id;

  BEGIN
    INSERT INTO public.mentor_messages (conversation_id, user_id, role, mode, content)
    VALUES (v_bob_conv_id, '11111111-1111-1111-1111-111111111111', 'user', 'explain', 'pretend to be alice');
    RAISE EXCEPTION 'FAIL: bob inserted a message forged as alice';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: cannot forge another user as the message author (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 5. Staff can read any conversation (support/abuse review); still cannot
--    edit or delete another user's messages (no policy permits it).
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.mentor_conversations WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF cnt <> 1 THEN RAISE EXCEPTION 'FAIL: admin should see alice''s conversation, saw %', cnt; END IF;
  RAISE NOTICE 'PASS: staff can read any conversation for support/abuse review';
END $$;

DO $$
DECLARE affected int;
BEGIN
  BEGIN
    UPDATE public.mentor_messages SET content = 'tampered' WHERE user_id = '11111111-1111-1111-1111-111111111111';
    GET DIAGNOSTICS affected = ROW_COUNT;
    IF affected <> 0 THEN RAISE EXCEPTION 'FAIL: admin edited another user''s message (% rows)', affected; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS: messages are immutable, even for staff';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL AI MENTOR RLS TESTS PASSED'
