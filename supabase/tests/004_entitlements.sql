-- ============================================================================
-- Entitlements regression tests: free plan auto-assigned, entitlements are
-- unforgeable by a client, admin comps and provider-style webhook grants
-- work, replay protection holds.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users (id, email) VALUES
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'admin@test.local');
UPDATE public.user_roles SET role = 'admin' WHERE user_id = '33333333-3333-3333-3333-333333333333';
INSERT INTO public.user_roles (user_id, role) VALUES ('33333333-3333-3333-3333-333333333333', 'admin') ON CONFLICT DO NOTHING;

CREATE OR REPLACE PROCEDURE test_act_as(p_user_id uuid) LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated')::text, false);
END;
$$;

-- ============================================================================
-- 1. New user is automatically on the free plan with its real limits.
-- ============================================================================
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_limit jsonb;
BEGIN
  SELECT public.get_entitlement('user', '11111111-1111-1111-1111-111111111111', 'lab_instances_concurrent') INTO v_limit;
  IF v_limit IS NULL OR v_limit::text <> '1' THEN
    RAISE EXCEPTION 'FAIL: expected free plan lab_instances_concurrent=1, got %', v_limit;
  END IF;

  SELECT public.get_entitlement('user', '11111111-1111-1111-1111-111111111111', 'cyber_range_access') INTO v_limit;
  IF v_limit::text <> 'false' THEN
    RAISE EXCEPTION 'FAIL: expected free plan cyber_range_access=false, got %', v_limit;
  END IF;
  RAISE NOTICE 'PASS: new user auto-provisioned on free plan with correct entitlements';
END $$;

-- ============================================================================
-- 2. A user cannot grant themselves a paid plan (no direct table write, and
--    set_active_subscription() itself refuses non-admin/non-service callers).
-- ============================================================================
DO $$
DECLARE v_pro_plan_id uuid;
BEGIN
  RESET ROLE;
  -- Slug deliberately NOT 'pro' -- that's now a real seeded plan (see
  -- 20260922000015_seed_pro_plan.sql), and this fixture must not collide
  -- with it outside this test's own transaction rollback.
  INSERT INTO public.plans (id, slug, name, price_cents, interval) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'test-plan-escalation-fixture', 'Pro', 1999, 'month')
  RETURNING id INTO v_pro_plan_id;
  INSERT INTO public.plan_entitlements (plan_id, key, value) VALUES
    (v_pro_plan_id, 'cyber_range_access', 'true');
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');

DO $$
BEGIN
  BEGIN
    INSERT INTO public.subscriptions (subject_type, subject_id, plan_id, status)
    VALUES ('user', '11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'active');
    RAISE EXCEPTION 'FAIL: alice inserted her own subscription directly';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: direct INSERT into subscriptions is rejected (%)', SQLSTATE;
  END;
END $$;

DO $$
BEGIN
  BEGIN
    PERFORM public.set_active_subscription('user', '11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'active', 'manual');
    RAISE EXCEPTION 'FAIL: alice called set_active_subscription() to upgrade herself';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: set_active_subscription() refuses a non-admin, non-service caller (%)', SQLSTATE;
  END;
END $$;

DO $$
DECLARE v_limit jsonb;
BEGIN
  SELECT public.get_entitlement('user', '11111111-1111-1111-1111-111111111111', 'cyber_range_access') INTO v_limit;
  IF v_limit::text <> 'false' THEN
    RAISE EXCEPTION 'FAIL: alice''s entitlement changed despite rejected escalation attempts (got %)', v_limit;
  END IF;
  RAISE NOTICE 'PASS: entitlement unchanged after rejected self-escalation attempts';
END $$;

-- ============================================================================
-- 3. Admin CAN grant a plan (manual comp), and it takes effect immediately.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_sub public.subscriptions;
BEGIN
  SELECT * INTO v_sub FROM public.set_active_subscription(
    'user', '11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'active', 'manual'
  );
  IF v_sub.granted_by <> '33333333-3333-3333-3333-333333333333' THEN
    RAISE EXCEPTION 'FAIL: manual grant not attributed to the granting admin';
  END IF;
  RAISE NOTICE 'PASS: admin can manually grant a plan, attributed to the admin';
END $$;

CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
DECLARE v_limit jsonb;
BEGIN
  SELECT public.get_entitlement('user', '11111111-1111-1111-1111-111111111111', 'cyber_range_access') INTO v_limit;
  IF v_limit::text <> 'true' THEN
    RAISE EXCEPTION 'FAIL: expected cyber_range_access=true after admin grant, got %', v_limit;
  END IF;
  RAISE NOTICE 'PASS: admin-granted entitlement is immediately effective';
END $$;

-- ============================================================================
-- 4. Only one active subscription row per subject: granting again supersedes,
--    does not stack.
-- ============================================================================
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_active_count int;
BEGIN
  PERFORM public.set_active_subscription('user', '11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'active', 'manual');
  SELECT count(*) INTO v_active_count FROM public.subscriptions
    WHERE subject_type = 'user' AND subject_id = '11111111-1111-1111-1111-111111111111'
      AND status IN ('trialing', 'active', 'past_due');
  IF v_active_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected exactly 1 active subscription, found %', v_active_count;
  END IF;
  RAISE NOTICE 'PASS: re-granting supersedes rather than stacking active subscriptions';
END $$;

-- ============================================================================
-- 5. Webhook replay protection: same (provider, provider_event_id) twice
--    is rejected by the unique constraint.
-- ============================================================================
RESET ROLE;
SET ROLE service_role;
DO $$
BEGIN
  INSERT INTO public.billing_webhook_events (provider, provider_event_id, event_type, payload)
  VALUES ('stripe', 'evt_test_123', 'invoice.paid', '{}'::jsonb);
END $$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.billing_webhook_events (provider, provider_event_id, event_type, payload)
    VALUES ('stripe', 'evt_test_123', 'invoice.paid', '{}'::jsonb);
    RAISE EXCEPTION 'FAIL: duplicate webhook event id was accepted';
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'PASS: duplicate webhook event id rejected (replay protection)';
  END;
END $$;

-- A client (even authenticated) can never write a fake webhook event.
CALL test_act_as('11111111-1111-1111-1111-111111111111');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.billing_webhook_events (provider, provider_event_id, event_type, payload)
    VALUES ('stripe', 'evt_forged', 'invoice.paid', '{}'::jsonb);
    RAISE EXCEPTION 'FAIL: authenticated user inserted a forged webhook event';
  EXCEPTION WHEN others THEN
    IF SQLSTATE = 'P0001' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: client cannot forge a billing webhook event (%)', SQLSTATE;
  END;
END $$;

-- ============================================================================
-- 6. The real seeded 'pro' plan (not the escalation-fixture plan above) --
--    the one the live billing checkout flows actually grant -- has real
--    entitlement values and, once active via set_active_subscription(),
--    resolves through get_entitlement() exactly like any other plan.
-- ============================================================================
RESET ROLE;
DO $$
DECLARE v_pro_plan_id uuid; v_limit jsonb;
BEGIN
  SELECT id INTO v_pro_plan_id FROM public.plans WHERE slug = 'pro';
  IF v_pro_plan_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: the real ''pro'' plan seeded by 20260922000015_seed_pro_plan.sql is missing';
  END IF;

  SELECT value INTO v_limit FROM public.plan_entitlements WHERE plan_id = v_pro_plan_id AND key = 'lab_instances_concurrent';
  IF v_limit IS NULL OR v_limit::text = '1' THEN
    RAISE EXCEPTION 'FAIL: the real pro plan should grant more than the free plan''s lab_instances_concurrent=1, got %', v_limit;
  END IF;

  PERFORM set_config('icorepen_test.pro_plan_id', v_pro_plan_id::text, false);
END $$;

-- set_active_subscription() only accepts an admin or service_role caller --
-- exactly what a real webhook handler runs as (createAdminClient() ==
-- service_role), and what a manual comp runs as (an admin session), never
-- the subject's own session (already proven unable to in section 2 above).
CALL test_act_as('33333333-3333-3333-3333-333333333333');
DO $$
DECLARE v_pro_plan_id uuid; v_limit jsonb;
BEGIN
  v_pro_plan_id := current_setting('icorepen_test.pro_plan_id')::uuid;
  PERFORM public.set_active_subscription('user', '11111111-1111-1111-1111-111111111111', v_pro_plan_id, 'active', 'stripe');

  SELECT public.get_entitlement('user', '11111111-1111-1111-1111-111111111111', 'cyber_range_access') INTO v_limit;
  IF v_limit::text <> 'true' THEN
    RAISE EXCEPTION 'FAIL: expected cyber_range_access=true on the real pro plan, got %', v_limit;
  END IF;
  RAISE NOTICE 'PASS: the real seeded pro plan grants real, better-than-free entitlements once active';
END $$;

RESET ROLE;
DROP PROCEDURE test_act_as(uuid);

ROLLBACK;

\echo 'ALL ENTITLEMENT TESTS PASSED'
