import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { verifyFlutterwaveSignature } from "@/lib/billing/flutterwave";
import { getFlutterwaveWebhookSecretHash, isFlutterwaveConfigured } from "@/lib/billing/env";
import { PRO_PLAN_SLUG, computePeriodEnd } from "@/lib/billing/plans";

interface FlutterwaveEvent {
  event: string;
  data: Record<string, unknown>;
}

/**
 * Flutterwave webhook. Same idempotency/processing discipline as the
 * Stripe/Paystack handlers -- see docs/adr/0011-live-billing-integration.md.
 *
 * Handles activation (a successful charge) and cancellation
 * (`subscription.cancelled`, downgrading back to `free`), matching the
 * Stripe/Paystack handlers' coverage. Cancellation is matched by
 * `provider_customer_id` rather than a subscription id: Flutterwave's
 * recurring-payment model doesn't expose a stable per-charge subscription
 * identifier the way Stripe's `customer.subscription.deleted` does, so the
 * (provider, provider_customer_id) pair set at activation time is the most
 * reliable real identifier available. The event name and payload shape
 * here are implemented against Flutterwave's documented webhook format;
 * verify both against your own account's actual deliveries when you
 * configure this for real (MANUAL_SETUP.md §4c) -- there is no live
 * Flutterwave account in this build environment to confirm against.
 */
export async function POST(request: Request) {
  if (!isFlutterwaveConfigured()) {
    return NextResponse.json({ error: "Flutterwave is not configured" }, { status: 503 });
  }

  const rawBody = await request.text();
  const signatureHeader = request.headers.get("verif-hash") ?? "";
  if (!verifyFlutterwaveSignature(signatureHeader, getFlutterwaveWebhookSecretHash())) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  let event: FlutterwaveEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const providerEventId = String(event.data.id ?? event.data.tx_ref ?? "");
  if (!providerEventId) {
    return NextResponse.json({ error: "Event missing an identifiable transaction id" }, { status: 400 });
  }

  const supabase = createAdminClient();

  const { data: logged, error: insertError } = await supabase
    .from("billing_webhook_events")
    .insert({
      provider: "flutterwave",
      provider_event_id: providerEventId,
      event_type: event.event ?? "unknown",
      payload: event as unknown as Record<string, unknown>,
    })
    .select("id")
    .single();

  if (insertError) {
    if (insertError.code === "23505") {
      return NextResponse.json({ received: true, duplicate: true });
    }
    console.error("Failed to log Flutterwave webhook event:", insertError);
    return NextResponse.json({ error: "internal error" }, { status: 500 });
  }

  try {
    if (event.data.status === "successful") {
      await handleChargeSuccessful(supabase, event.data);
    } else if (event.event === "subscription.cancelled") {
      await handleSubscriptionCancelled(supabase, event.data);
    }
    await supabase
      .from("billing_webhook_events")
      .update({ status: "processed", processed_at: new Date().toISOString() })
      .eq("id", logged.id);
  } catch (err) {
    console.error("Failed to process Flutterwave webhook event:", err);
    await supabase
      .from("billing_webhook_events")
      .update({ status: "failed", error: err instanceof Error ? err.message : String(err) })
      .eq("id", logged.id);
    return NextResponse.json({ error: "processing failed" }, { status: 500 });
  }

  return NextResponse.json({ received: true });
}

async function handleChargeSuccessful(supabase: ReturnType<typeof createAdminClient>, data: Record<string, unknown>) {
  const meta = data.meta as { user_id?: string } | undefined;
  const userId = meta?.user_id;
  if (!userId) return;

  const { data: plan } = await supabase.from("plans").select("id, interval").eq("slug", PRO_PLAN_SLUG).single();
  if (!plan) return;

  const customer = data.customer as { id?: string | number } | undefined;

  await supabase.rpc("set_active_subscription", {
    p_subject_type: "user",
    p_subject_id: userId,
    p_plan_id: plan.id,
    p_status: "active",
    p_provider: "flutterwave",
    p_provider_customer_id: customer?.id != null ? String(customer.id) : null,
    p_provider_subscription_id: data.id != null ? String(data.id) : null,
    p_current_period_end: computePeriodEnd(plan.interval).toISOString(),
  });
}

async function handleSubscriptionCancelled(supabase: ReturnType<typeof createAdminClient>, data: Record<string, unknown>) {
  const customer = data.customer as { id?: string | number } | undefined;
  const providerCustomerId = customer?.id != null ? String(customer.id) : null;
  if (!providerCustomerId) return;

  // Scoped to the currently active-ish row, not just a bare match on
  // provider_customer_id: that id persists across a customer's whole
  // history with Flutterwave, so a past cancel-then-resubscribe can leave
  // more than one historical row sharing it. Without this filter,
  // .maybeSingle() would error on >1 match.
  const { data: existing } = await supabase
    .from("subscriptions")
    .select("subject_type, subject_id")
    .eq("provider", "flutterwave")
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
