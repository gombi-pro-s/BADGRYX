import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { verifyPaystackSignature } from "@/lib/billing/paystack";
import { getPaystackSecretKey, isPaystackConfigured } from "@/lib/billing/env";
import { PRO_PLAN_SLUG, computePeriodEnd } from "@/lib/billing/plans";

interface PaystackEvent {
  event: string;
  data: Record<string, unknown>;
}

/**
 * Paystack webhook. Same idempotency/processing discipline as the Stripe
 * handler -- see that route's comment and
 * docs/adr/0011-live-billing-integration.md. Paystack signs with the same
 * secret key used for API calls (x-paystack-signature), not a separate
 * webhook secret.
 */
export async function POST(request: Request) {
  if (!isPaystackConfigured()) {
    return NextResponse.json({ error: "Paystack is not configured" }, { status: 503 });
  }

  const rawBody = await request.text();
  const signatureHeader = request.headers.get("x-paystack-signature") ?? "";
  if (!verifyPaystackSignature(rawBody, signatureHeader, getPaystackSecretKey())) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  let event: PaystackEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  // Paystack does not send a stable top-level event id -- the transaction
  // reference (or subscription code) is the closest real idempotency key
  // for a given event type.
  const providerEventId = `${event.event}:${(event.data.reference ?? event.data.subscription_code ?? event.data.id) as string}`;

  const supabase = createAdminClient();

  const { data: logged, error: insertError } = await supabase
    .from("billing_webhook_events")
    .insert({
      provider: "paystack",
      provider_event_id: providerEventId,
      event_type: event.event,
      payload: event as unknown as Record<string, unknown>,
    })
    .select("id")
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      return NextResponse.json({ received: true, duplicate: true });
    }
    console.error("Failed to log Paystack webhook event:", insertError);
    return NextResponse.json({ error: "internal error" }, { status: 500 });
  }

  try {
    if (event.event === "charge.success") {
      await handleChargeSuccess(supabase, event.data);
    } else if (event.event === "subscription.disable") {
      await handleSubscriptionDisabled(supabase, event.data);
    }
    await supabase
      .from("billing_webhook_events")
      .update({ status: "processed", processed_at: new Date().toISOString() })
      .eq("id", logged.id);
  } catch (err) {
    console.error("Failed to process Paystack webhook event:", err);
    await supabase
      .from("billing_webhook_events")
      .update({ status: "failed", error: err instanceof Error ? err.message : String(err) })
      .eq("id", logged.id);
    return NextResponse.json({ error: "processing failed" }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}

async function handleChargeSuccess(supabase: ReturnType<typeof createAdminClient>, data: Record<string, unknown>) {
  const metadata = data.metadata as { user_id?: string } | undefined;
  const userId = metadata?.user_id;
  if (!userId) return;

  const { data: plan } = await supabase.from("plans").select("id, interval").eq("slug", PRO_PLAN_SLUG).single();
  if (!plan) return;

  const customer = data.customer as { customer_code?: string } | undefined;

  await supabase.rpc("set_active_subscription", {
    p_subject_type: "user",
    p_subject_id: userId,
    p_plan_id: plan.id,
    p_status: "active",
    p_provider: "paystack",
    p_provider_customer_id: customer?.customer_code ?? null,
    p_provider_subscription_id: (data.subscription_code as string) ?? null,
    p_current_period_end: computePeriodEnd(plan.interval).toISOString(),
  });
}

async function handleSubscriptionDisabled(supabase: ReturnType<typeof createAdminClient>, data: Record<string, unknown>) {
  const customer = data.customer as { customer_code?: string } | undefined;
  const providerCustomerId = customer?.customer_code;
  if (!providerCustomerId) return;

  // Scoped to the currently active-ish row, not just a bare match on
  // provider_customer_id: that id persists across a customer's whole
  // history with Paystack, so a past cancel-then-resubscribe can leave
  // more than one historical row sharing it. Without this filter,
  // .maybeSingle() would error on >1 match.
  const { data: existing } = await supabase
    .from("subscriptions")
    .select("subject_type, subject_id")
    .eq("provider", "paystack")
    .eq("provider_customer_id", providerCustomerId)
    .in("status", ["trialing", "active", "past_due"])
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
