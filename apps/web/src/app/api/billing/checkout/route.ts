import { NextResponse } from "next/server";
import { z } from "zod";
import { requireApiUser } from "@/lib/auth/api";
import {
  isStripeConfigured,
  isPaystackConfigured,
  isFlutterwaveConfigured,
  getStripePriceIdPro,
  getPaystackPlanCodePro,
  getFlutterwavePaymentPlanIdPro,
} from "@/lib/billing/env";
import { createStripeCheckoutSession } from "@/lib/billing/stripe-client";
import { createPaystackTransaction } from "@/lib/billing/paystack-client";
import { createFlutterwavePayment } from "@/lib/billing/flutterwave-client";

const bodySchema = z.object({ provider: z.enum(["stripe", "paystack", "flutterwave"]) });

function siteUrl(): string {
  return process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
}

/**
 * The mobile-facing equivalent of settings/billing/actions.ts's three
 * createXCheckoutAction()s -- same provider calls, same success/cancel
 * URLs (always the web app's /settings/billing, since that's where the
 * webhook-driven entitlement update surfaces regardless of which client
 * started checkout), but returns the checkout URL as JSON instead of
 * calling redirect(), which only makes sense for a browser follow. The
 * mobile client opens that URL itself (see ADR 0047) -- this route never
 * runs a payment provider's SDK or collects card details, exactly like
 * the web action it mirrors.
 */
export async function POST(request: Request) {
  const auth = await requireApiUser(request);
  if ("unauthorized" in auth) return auth.unauthorized;
  const { user } = auth;

  const parsed = bodySchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) {
    return NextResponse.json({ error: "Invalid provider." }, { status: 400 });
  }
  if (!user.email) {
    return NextResponse.json({ error: "Your account has no email on file." }, { status: 400 });
  }

  try {
    let url: string;
    switch (parsed.data.provider) {
      case "stripe": {
        if (!isStripeConfigured()) {
          return NextResponse.json({ error: "Stripe isn't configured yet -- see MANUAL_SETUP.md." }, { status: 400 });
        }
        ({ url } = await createStripeCheckoutSession({
          priceId: getStripePriceIdPro(),
          userId: user.id,
          userEmail: user.email,
          successUrl: `${siteUrl()}/settings/billing?success=stripe`,
          cancelUrl: `${siteUrl()}/settings/billing?canceled=stripe`,
        }));
        break;
      }
      case "paystack": {
        if (!isPaystackConfigured()) {
          return NextResponse.json({ error: "Paystack isn't configured yet -- see MANUAL_SETUP.md." }, { status: 400 });
        }
        ({ url } = await createPaystackTransaction({
          planCode: getPaystackPlanCodePro(),
          userId: user.id,
          userEmail: user.email,
          callbackUrl: `${siteUrl()}/settings/billing?success=paystack`,
        }));
        break;
      }
      case "flutterwave": {
        if (!isFlutterwaveConfigured()) {
          return NextResponse.json({ error: "Flutterwave isn't configured yet -- see MANUAL_SETUP.md." }, { status: 400 });
        }
        ({ url } = await createFlutterwavePayment({
          paymentPlanId: getFlutterwavePaymentPlanIdPro(),
          userId: user.id,
          userEmail: user.email,
          amountUsd: 19,
          redirectUrl: `${siteUrl()}/settings/billing?success=flutterwave`,
        }));
        break;
      }
    }
    return NextResponse.json({ url });
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : "Failed to start checkout." }, { status: 502 });
  }
}
