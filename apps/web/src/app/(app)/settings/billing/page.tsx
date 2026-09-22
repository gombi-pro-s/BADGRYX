import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { isStripeConfigured, isPaystackConfigured, isFlutterwaveConfigured } from "@/lib/billing/env";
import { createStripeCheckoutAction, createPaystackCheckoutAction, createFlutterwaveCheckoutAction } from "./actions";
import { UpgradeButton } from "./upgrade-button";

export const metadata: Metadata = { title: "Billing" };

export default async function BillingPage({
  searchParams,
}: {
  searchParams: Promise<{ success?: string; canceled?: string }>;
}) {
  const { success, canceled } = await searchParams;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: subscription } = await supabase
    .from("subscriptions")
    .select("plan_id, status, provider, current_period_end")
    .eq("subject_type", "user")
    .eq("subject_id", user.id)
    .in("status", ["trialing", "active", "past_due"])
    .maybeSingle();

  const { data: plan } = subscription
    ? await supabase.from("plans").select("id, slug, name, description, price_cents, currency, interval").eq("id", subscription.plan_id).single()
    : { data: null };

  const { data: entitlements } = plan
    ? await supabase.from("plan_entitlements").select("key, value").eq("plan_id", plan.id)
    : { data: [] };

  const isPro = plan?.slug === "pro";

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/settings" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; Settings
      </Link>
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Billing</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Entitlements are enforced server-side ({" "}
        <code className="rounded bg-background-subtle px-1 py-0.5 text-xs">get_entitlement()</code>) the moment a
        real payment provider confirms your subscription -- never before, and never by trusting anything this
        page sends.
      </p>

      {success && (
        <div className="mb-6 rounded-lg border border-success/30 bg-success-muted p-4 text-sm text-success">
          Payment received. Your plan updates as soon as the webhook is processed -- usually within a few
          seconds. Refresh if it hasn&apos;t updated yet.
        </div>
      )}
      {canceled && (
        <div className="mb-6 rounded-lg border border-border bg-surface p-4 text-sm text-foreground-muted">
          Checkout was canceled. No charge was made.
        </div>
      )}

      <div className="mb-8 rounded-lg border border-border bg-surface p-5">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm font-semibold text-foreground">{plan?.name ?? "Free"}</p>
            {subscription && <p className="mt-0.5 text-xs text-foreground-subtle">{subscription.status}</p>}
          </div>
          {isPro && (
            <span className="rounded-full bg-success-muted px-2.5 py-0.5 text-xs font-medium text-success">Pro</span>
          )}
        </div>
        {plan?.description && <p className="mt-3 text-sm text-foreground-muted">{plan.description}</p>}
        {entitlements && entitlements.length > 0 && (
          <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-xs">
            {entitlements.map((e) => (
              <div key={e.key} className="flex justify-between gap-2 border-t border-border pt-2">
                <dt className="text-foreground-subtle">{e.key.replace(/_/g, " ")}</dt>
                <dd className="text-foreground">{JSON.stringify(e.value)}</dd>
              </div>
            ))}
          </dl>
        )}
      </div>

      {!isPro && (
        <div className="rounded-lg border border-border bg-surface p-5">
          <h2 className="mb-1 text-sm font-semibold text-foreground">Upgrade to Pro</h2>
          <p className="mb-4 text-xs text-foreground-subtle">
            More concurrent labs, a bigger daily AI Mentor allowance, cyber range access, team management, and
            advanced reports. $19/month.
          </p>
          <div className="space-y-3">
            <UpgradeButton label="Upgrade with Stripe" configured={isStripeConfigured()} onCheckout={createStripeCheckoutAction} />
            <UpgradeButton label="Upgrade with Paystack" configured={isPaystackConfigured()} onCheckout={createPaystackCheckoutAction} />
            <UpgradeButton
              label="Upgrade with Flutterwave"
              configured={isFlutterwaveConfigured()}
              onCheckout={createFlutterwaveCheckoutAction}
            />
          </div>
        </div>
      )}
    </div>
  );
}
