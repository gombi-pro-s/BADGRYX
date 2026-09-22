-- ============================================================================
-- Proves the subscription-cleanup triggers (20260922000023) actually work:
-- subscriptions.subject_id has no real FK (it's polymorphic), so without
-- these triggers a deleted user's or organization's subscription row would
-- be orphaned forever. Also proves the triggers are correctly scoped: only
-- subscriptions belonging to the deleted subject are removed.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local');

-- alice's own auth.users insert already fired handle_new_user_free_plan(),
-- giving her a real 'free' subscription -- this test relies on that real
-- trigger output rather than planting a synthetic subscription row.

INSERT INTO public.organizations (id, slug, name, created_by)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'sub-cleanup-org', 'Sub Cleanup Org', '11111111-1111-1111-1111-111111111111');

INSERT INTO public.subscriptions (subject_type, subject_id, plan_id, status, provider)
VALUES ('organization', 'aaaaaaaa-0000-0000-0000-000000000001', (SELECT id FROM public.plans WHERE slug = 'pro'), 'active', 'manual');

-- ============================================================================
-- 1. Deleting alice removes HER subscription, leaves bob's and the org's
--    untouched.
-- ============================================================================
DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.subscriptions
    WHERE subject_type = 'user' AND subject_id = '11111111-1111-1111-1111-111111111111';
  IF v_count = 0 THEN RAISE EXCEPTION 'FAIL: alice should have a real free-plan subscription before deletion'; END IF;
END $$;

DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111111';

DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.subscriptions
    WHERE subject_type = 'user' AND subject_id = '11111111-1111-1111-1111-111111111111';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: alice''s subscription should have been deleted along with her, got % rows left', v_count;
  END IF;
  RAISE NOTICE 'PASS: deleting a user deletes their own subscription row, not just leaves it orphaned';

  SELECT count(*) INTO v_count FROM public.subscriptions
    WHERE subject_type = 'user' AND subject_id = '22222222-2222-2222-2222-222222222222';
  IF v_count = 0 THEN
    RAISE EXCEPTION 'FAIL: bob''s own subscription should be unaffected by alice''s deletion';
  END IF;
  RAISE NOTICE 'PASS: a different user''s subscription is unaffected';

  SELECT count(*) INTO v_count FROM public.subscriptions
    WHERE subject_type = 'organization' AND subject_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: the organization''s subscription should survive its creator''s deletion, got % rows', v_count;
  END IF;
  RAISE NOTICE 'PASS: an organization''s subscription survives its creator being deleted (org itself survives per ADR 0012)';
END $$;

-- ============================================================================
-- 2. Deleting the organization removes ITS subscription too.
-- ============================================================================
DELETE FROM public.organizations WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';

DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.subscriptions
    WHERE subject_type = 'organization' AND subject_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FAIL: the organization''s subscription should have been deleted along with it, got % rows left', v_count;
  END IF;
  RAISE NOTICE 'PASS: deleting an organization deletes its own subscription row';
END $$;

ROLLBACK;

\echo 'ALL SUBSCRIPTION CLEANUP TESTS PASSED'
