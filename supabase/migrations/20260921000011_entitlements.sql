-- ============================================================================
-- Entitlement / billing engine (section 28), built provider-agnostic per
-- docs/adr/0005-entitlements-before-billing.md: a live payment provider
-- (Stripe/Paystack/Flutterwave) is deliberately NOT wired up yet, but the
-- server-side entitlement model that all product code must check against is
-- real and complete. When a provider is connected, its webhook handler only
-- needs to write rows into `subscriptions` and `billing_webhook_events`
-- below -- no product code changes.
--
-- Absolute rule (section 28): entitlements are NEVER client-settable.
-- subscriptions/plan_entitlements have no client write path at all --
-- only service_role (the webhook handler) or an admin (manual comps,
-- support actions) may write them.
-- ============================================================================

CREATE TYPE public.billing_interval AS ENUM ('free', 'month', 'year', 'lifetime');
CREATE TYPE public.subscription_status AS ENUM (
  'trialing', 'active', 'past_due', 'canceled', 'expired', 'incomplete'
);
CREATE TYPE public.billing_subject_type AS ENUM ('user', 'organization');

CREATE TABLE public.plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  description text,
  price_cents integer NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
  currency text NOT NULL DEFAULT 'USD',
  interval public.billing_interval NOT NULL DEFAULT 'free',
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.plans IS
  'Plan catalog. Prices are informational/display only for now -- actual '
  'checkout happens through whichever payment provider is later connected; '
  'see MANUAL_SETUP.md.';

-- Flexible key -> value entitlements per plan, e.g.
--   ('pro', 'lab_instances_concurrent', '3'), ('pro', 'ai_mentor_daily_requests', '50'),
--   ('pro', 'cyber_range_access', 'true'), ('team', 'seats', '10')
-- Numeric/boolean limits are stored as jsonb scalars so public.get_entitlement()
-- has one consistent return type regardless of the underlying limit's shape.
CREATE TABLE public.plan_entitlements (
  plan_id uuid NOT NULL REFERENCES public.plans (id) ON DELETE CASCADE,
  key text NOT NULL,
  value jsonb NOT NULL,
  PRIMARY KEY (plan_id, key)
);

CREATE TABLE public.subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type public.billing_subject_type NOT NULL,
  subject_id uuid NOT NULL, -- auth.users.id or organizations.id depending on subject_type
  plan_id uuid NOT NULL REFERENCES public.plans (id),
  status public.subscription_status NOT NULL DEFAULT 'active',
  provider text, -- 'stripe' | 'paystack' | 'flutterwave' | 'manual' (admin comp) | NULL (free plan)
  provider_customer_id text,
  provider_subscription_id text,
  current_period_start timestamptz NOT NULL DEFAULT now(),
  current_period_end timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  canceled_at timestamptz,
  trial_end timestamptz,
  granted_by uuid REFERENCES auth.users (id), -- set for provider='manual' comps
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_subscription_unique UNIQUE (provider, provider_subscription_id)
);

CREATE INDEX subscriptions_subject_idx ON public.subscriptions (subject_type, subject_id, status);

COMMENT ON TABLE public.subscriptions IS
  'One row per active/historical subscription. A subject (user or org) can '
  'have multiple historical rows but should have at most one row with '
  'status IN (trialing, active, past_due) at a time -- enforced by '
  'public.set_active_subscription(), never by direct insert.';

-- Idempotency / replay protection (section 28): a webhook provider may
-- redeliver the same event; provider_event_id is unique so redelivery is a
-- no-op, not a double-processed entitlement change.
CREATE TYPE public.webhook_event_status AS ENUM ('received', 'processed', 'failed', 'ignored');

CREATE TABLE public.billing_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  provider_event_id text NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  status public.webhook_event_status NOT NULL DEFAULT 'received',
  error text,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE (provider, provider_event_id)
);

COMMENT ON TABLE public.billing_webhook_events IS
  'Raw webhook log with a hard uniqueness constraint on (provider, '
  'provider_event_id) for replay protection. Never logs card numbers or '
  'full payment-method details -- providers do not send them in these '
  'events, but the constraint is documented here as a reminder for anyone '
  'wiring in a new provider.';

-- ----------------------------------------------------------------------------
-- get_entitlement: the single function all product code should call to
-- check a limit/feature flag. Resolves the subject's current active
-- subscription's plan, falls back to the 'free' plan's value if the
-- subject has no active subscription row at all, and returns NULL if the
-- key isn't defined anywhere (caller must treat NULL as "not entitled").
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_entitlement(
  p_subject_type public.billing_subject_type,
  p_subject_id uuid,
  p_key text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_plan_id uuid;
  v_value jsonb;
BEGIN
  SELECT plan_id INTO v_plan_id
  FROM public.subscriptions
  WHERE subject_type = p_subject_type AND subject_id = p_subject_id
    AND status IN ('trialing', 'active', 'past_due')
  ORDER BY current_period_start DESC
  LIMIT 1;

  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id FROM public.plans WHERE slug = 'free';
  END IF;

  SELECT value INTO v_value FROM public.plan_entitlements
    WHERE plan_id = v_plan_id AND key = p_key;

  RETURN v_value;
END;
$$;

COMMENT ON FUNCTION public.get_entitlement IS
  'Server-side entitlement check. Callable by authenticated (to check their '
  'own limits client-side for UX) but MUST also be re-checked by any server '
  'action/API route before performing the gated operation -- a client-side '
  'check is UX only, never the enforcement point (section 28).';

REVOKE ALL ON FUNCTION public.get_entitlement FROM public;
GRANT EXECUTE ON FUNCTION public.get_entitlement TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- set_active_subscription: the only way to create/change a subscription.
-- Ends any existing trialing/active/past_due row for the subject before
-- inserting the new one, so "at most one active row per subject" holds
-- without a partial-unique-index race (status changes, e.g.
-- active -> canceled, are not swaps of *which* row is active).
-- Callable only by service_role (the webhook handler) or an admin (manual
-- comp) -- never by the subscription's own subject.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_active_subscription(
  p_subject_type public.billing_subject_type,
  p_subject_id uuid,
  p_plan_id uuid,
  p_status public.subscription_status,
  p_provider text,
  p_provider_customer_id text DEFAULT NULL,
  p_provider_subscription_id text DEFAULT NULL,
  p_current_period_end timestamptz DEFAULT NULL,
  p_trial_end timestamptz DEFAULT NULL
)
  RETURNS public.subscriptions
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_sub public.subscriptions;
BEGIN
  IF NOT (public.is_admin() OR auth.role() = 'service_role') THEN
    RAISE EXCEPTION 'insufficient privilege to modify subscriptions' USING ERRCODE = '42501';
  END IF;

  UPDATE public.subscriptions
    SET status = 'expired', updated_at = now()
    WHERE subject_type = p_subject_type AND subject_id = p_subject_id
      AND status IN ('trialing', 'active', 'past_due');

  INSERT INTO public.subscriptions (
    subject_type, subject_id, plan_id, status, provider,
    provider_customer_id, provider_subscription_id,
    current_period_end, trial_end,
    granted_by
  ) VALUES (
    p_subject_type, p_subject_id, p_plan_id, p_status, p_provider,
    p_provider_customer_id, p_provider_subscription_id,
    p_current_period_end, p_trial_end,
    CASE WHEN p_provider = 'manual' THEN auth.uid() ELSE NULL END
  )
  RETURNING * INTO v_sub;

  PERFORM public.log_audit_event('subscription.changed', p_subject_type::text, p_subject_id::text, NULL,
    jsonb_build_object('plan_id', p_plan_id, 'status', p_status, 'provider', p_provider));

  RETURN v_sub;
END;
$$;

REVOKE ALL ON FUNCTION public.set_active_subscription FROM public;
GRANT EXECUTE ON FUNCTION public.set_active_subscription TO authenticated, service_role;

-- New users start on the free plan automatically.
CREATE OR REPLACE FUNCTION public.handle_new_user_free_plan()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_free_plan_id uuid;
BEGIN
  SELECT id INTO v_free_plan_id FROM public.plans WHERE slug = 'free';
  IF v_free_plan_id IS NOT NULL THEN
    INSERT INTO public.subscriptions (subject_type, subject_id, plan_id, status, provider)
    VALUES ('user', NEW.id, v_free_plan_id, 'active', NULL);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created_free_plan
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_free_plan();

CREATE TRIGGER plans_set_updated_at BEFORE UPDATE ON public.plans FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER subscriptions_set_updated_at BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Seed the free plan itself (not really "seed data" so much as a structural
-- default every environment needs to function -- every new user is wired to
-- it by the trigger above).
-- ----------------------------------------------------------------------------

INSERT INTO public.plans (slug, name, description, price_cents, interval, sort_order) VALUES
  ('free', 'Free', 'Get started with core lessons, guided labs, and a limited AI Mentor allowance.', 0, 'free', 0);

INSERT INTO public.plan_entitlements (plan_id, key, value)
SELECT id, k, v::jsonb FROM public.plans, (VALUES
  ('lab_instances_concurrent', '1'),
  ('ai_mentor_daily_requests', '10'),
  ('cyber_range_access', 'false'),
  ('team_management', 'false'),
  ('advanced_reports', 'false')
) AS kv(k, v)
WHERE plans.slug = 'free';
