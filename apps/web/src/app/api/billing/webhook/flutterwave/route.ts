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
 * Known limitation, documented rather than silently missing: this build
 * only handles activation (a successful charge). Flutterwave's recurring-
 * subscription cancellation events vary more by integration shape than
 * Stripe's/Paystack's, so reliable auto-downgrade-on-cancel is implemented
 * for Stripe only in v1 -- a Flutterwave subscriber who cancels on
 * Flutterwave's side needs an admin manual-comp change (or a follow-up
 * migration) until that's added.
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
