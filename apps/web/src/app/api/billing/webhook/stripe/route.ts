import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { verifyStripeSignature } from "@/lib/billing/stripe";
import { getStripeWebhookSecret, isStripeConfigured } from "@/lib/billing/env";
import { PRO_PLAN_SLUG, computePeriodEnd } from "@/lib/billing/plans";

interface StripeEvent {
  id: string;
  type: string;
  data: { object: Record<string, unknown> };
}

/**
 * Stripe webhook: the only server-side entry point that turns a real
 * payment into a real subscription. Every event is logged to
 * billing_webhook_events first (idempotent on (provider, provider_event_id)
 * -- Stripe redelivers on a non-2xx response, and a duplicate delivery must
 * be a no-op, not a double-activation), then processed, then marked
 * processed/failed. See docs/adr/0011-live-billing-integration.md.
 */
export async function POST(request: Request) {
  if (!isStripeConfigured()) {
    return NextResponse.json({ error: "Stripe is not configured" }, { status: 503 });
  }

  const rawBody = await request.text();
  const signatureHeader = request.headers.get("stripe-signature");
  if (!signatureHeader) {
    return NextResponse.json({ error: "Missing Stripe-Signature header" }, { status: 400 });
  }
  if (!verifyStripeSignature(rawBody, signatureHeader, getStripeWebhookSecret())) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const supabase = createAdminClient();

  const { data: logged, error: insertError } = await supabase
    .from("billing_webhook_events")
    .insert({
      provider: "stripe",
      provider_event_id: event.id,
      event_type: event.type,
      payload: event as unknown as Record<string, unknown>,
    })
    .select("id")
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      return NextResponse.json({ received: true, duplicate: true });
    }
    console.error("Failed to log Stripe webhook event:", insertError);
    return NextResponse.json({ error: "internal error" }, { status: 500 });
  }

  try {
    if (event.type === "checkout.session.completed") {
      await handleCheckoutCompleted(supabase, event.data.object);
    } else if (event.type === "customer.subscription.deleted") {
      await handleSubscriptionDeleted(supabase, event.data.object);
    }
    await supabase
      .from("billing_webhook_events")
      .update({ status: "processed", processed_at: new Date().toISOString() })
      .eq("id", logged.id);
  } catch (err) {
    console.error("Failed to process Stripe webhook event:", err);
    await supabase
      .from("billing_webhook_events")
      .update({ status: "failed", error: err instanceof Error ? err.message : String(err) })
      .eq("id", logged.id);
    return NextResponse.json({ error: "processing failed" }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}

async function handleCheckoutCompleted(supabase: ReturnType<typeof createAdminClient>, session: Record<string, unknown>) {
  const userId = session.client_reference_id as string | undefined;
  if (!userId) return;

  const { data: plan } = await supabase.from("plans").select("id, interval").eq("slug", PRO_PLAN_SLUG).single();
  if (!plan) return;

  await supabase.rpc("set_active_subscription", {
    p_subject_type: "user",
    p_subject_id: userId,
    p_plan_id: plan.id,
    p_status: "active",
    p_provider: "stripe",
    p_provider_customer_id: (session.customer as string) ?? null,
    p_provider_subscription_id: (session.subscription as string) ?? null,
    p_current_period_end: computePeriodEnd(plan.interval).toISOString(),
  });
}

async function handleSubscriptionDeleted(supabase: ReturnType<typeof createAdminClient>, subscription: Record<string, unknown>) {
  const providerSubscriptionId = subscription.id as string | undefined;
  if (!providerSubscriptionId) return;

  const { data: existing } = await supabase
    .from("subscriptions")
    .select("subject_type, subject_id")
    .eq("provider_subscription_id", providerSubscriptionId)
    .maybeSingle();
  if (!existing) return;

  const { data: freePlan } = await supabase.from("plans").select("id").eq("slug", "free").single();
  if (!freePlan) return;

  await supabase.rpc("set_active_subscription", {
    p_subject_type: existing.subject_type,
    p_subject_id: existing.subject_id,
    p_plan_id: freePlan.id,
    p_status: "active",
    p_provider: null,
  });
}
