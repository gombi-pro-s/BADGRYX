"use server";

import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { isStripeConfigured, isPaystackConfigured, isFlutterwaveConfigured, getStripePriceIdPro, getPaystackPlanCodePro, getFlutterwavePaymentPlanIdPro } from "@/lib/billing/env";
import { createStripeCheckoutSession } from "@/lib/billing/stripe-client";
import { createPaystackTransaction } from "@/lib/billing/paystack-client";
import { createFlutterwavePayment } from "@/lib/billing/flutterwave-client";

export interface CheckoutState {
  error: string | null;
}

function siteUrl(): string {
  return process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
}

export async function createStripeCheckoutAction(): Promise<CheckoutState> {
  const user = await requireUser();
  if (!isStripeConfigured()) {
    return { error: "Stripe isn't configured yet -- see MANUAL_SETUP.md." };
  }
  if (!user.email) {
    return { error: "Your account has no email on file." };
  }

  let url: string;
  try {
    const session = await createStripeCheckoutSession({
      priceId: getStripePriceIdPro(),
      userId: user.id,
      userEmail: user.email,
      successUrl: `${siteUrl()}/settings/billing?success=stripe`,
      cancelUrl: `${siteUrl()}/settings/billing?canceled=stripe`,
    });
    url = session.url;
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Failed to start Stripe checkout." };
  }

  redirect(url);
}

export async function createPaystackCheckoutAction(): Promise<CheckoutState> {
  const user = await requireUser();
  if (!isPaystackConfigured()) {
    return { error: "Paystack isn't configured yet -- see MANUAL_SETUP.md." };
  }
  if (!user.email) {
    return { error: "Your account has no email on file." };
  }

  let url: string;
  try {
    const transaction = await createPaystackTransaction({
      planCode: getPaystackPlanCodePro(),
      userId: user.id,
      userEmail: user.email,
      callbackUrl: `${siteUrl()}/settings/billing?success=paystack`,
    });
    url = transaction.url;
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Failed to start Paystack checkout." };
  }

  redirect(url);
}

export async function createFlutterwaveCheckoutAction(): Promise<CheckoutState> {
  const user = await requireUser();
  if (!isFlutterwaveConfigured()) {
    return { error: "Flutterwave isn't configured yet -- see MANUAL_SETUP.md." };
  }
  if (!user.email) {
    return { error: "Your account has no email on file." };
  }

  let url: string;
  try {
    const payment = await createFlutterwavePayment({
      paymentPlanId: getFlutterwavePaymentPlanIdPro(),
      userId: user.id,
      userEmail: user.email,
      amountUsd: 19,
      redirectUrl: `${siteUrl()}/settings/billing?success=flutterwave`,
    });
    url = payment.url;
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Failed to start Flutterwave checkout." };
  }

  redirect(url);
}
