-- ============================================================================
-- Seed the 'pro' plan: until now only 'free' existed (the structural
-- default every new user is auto-enrolled on), so there was nothing to
-- actually upgrade to. This is the one paid tier the live billing
-- integration (Stripe/Paystack/Flutterwave checkout + webhooks, see
-- docs/adr/0011-live-billing-integration.md) sells.
-- ============================================================================

INSERT INTO public.plans (slug, name, description, price_cents, currency, interval, sort_order) VALUES
  ('pro', 'Pro', 'More concurrent labs, a bigger daily AI Mentor allowance, cyber range access, team management, and advanced reports.', 1900, 'USD', 'month', 1);

INSERT INTO public.plan_entitlements (plan_id, key, value)
SELECT id, k, v::jsonb FROM public.plans, (VALUES
  ('lab_instances_concurrent', '5'),
  ('ai_mentor_daily_requests', '100'),
  ('scanner_daily_scans', '50'),
  ('scanner_daily_enrichments', '200'),
  ('cyber_range_access', 'true'),
  ('team_management', 'true'),
  ('advanced_reports', 'true')
) AS kv(k, v)
WHERE plans.slug = 'pro';
