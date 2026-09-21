-- ============================================================================
-- RLS: entitlements / billing.
-- ============================================================================

ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans FORCE ROW LEVEL SECURITY;
CREATE POLICY plans_select_active_or_staff ON public.plans
  FOR SELECT TO anon, authenticated USING (is_active OR public.is_staff());
CREATE POLICY plans_staff_write ON public.plans
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

ALTER TABLE public.plan_entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_entitlements FORCE ROW LEVEL SECURITY;
CREATE POLICY plan_entitlements_select_all ON public.plan_entitlements
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY plan_entitlements_staff_write ON public.plan_entitlements
  FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- subscriptions: readable by the subject (own user subscription, or an
-- org_admin/team_owner for their organization's subscription) and by staff.
-- Deliberately NO INSERT/UPDATE/DELETE policy for authenticated at all --
-- the only write path is public.set_active_subscription(), which itself
-- re-checks is_admin() OR service_role internally as defense in depth.
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY subscriptions_select_subject_or_staff ON public.subscriptions
  FOR SELECT TO authenticated
  USING (
    public.is_staff()
    OR (subject_type = 'user' AND subject_id = auth.uid())
    OR (subject_type = 'organization' AND public.is_org_admin(subject_id))
  );

ALTER TABLE public.billing_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_webhook_events FORCE ROW LEVEL SECURITY;
CREATE POLICY billing_webhook_events_select_admin ON public.billing_webhook_events
  FOR SELECT TO authenticated USING (public.is_admin());
-- No INSERT/UPDATE/DELETE policy for authenticated/anon: only service_role
-- (BYPASSRLS), used exclusively by the server-side webhook handler, may
-- write here. A client can never inject a fake "payment succeeded" event.
