-- ============================================================================
-- Rate-limit the security scanner through the real entitlement engine
-- (get_entitlement / plan_entitlements, see 20260921000011_entitlements.sql),
-- the same way the AI Mentor's ai_mentor_daily_requests key already works --
-- not a separate, disconnected quota system.
-- ============================================================================

INSERT INTO public.plan_entitlements (plan_id, key, value)
SELECT id, 'scanner_daily_scans', '5'::jsonb FROM public.plans WHERE slug = 'free';
