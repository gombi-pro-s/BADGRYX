import "server-only";

import { buildStripeCheckoutParams, type StripeCheckoutParams } from "./stripe";
import { getStripeSecretKey } from "./env";

export class StripeApiError extends Error {}

/** Creates a real Stripe Checkout Session and returns its hosted URL. */
export async function createStripeCheckoutSession(params: StripeCheckoutParams): Promise<{ url: string }> {
  const body = buildStripeCheckoutParams(params);

  const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getStripeSecretKey()}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  const data = await response.json().catch(() => null);
  if (!response.ok || !data?.url) {
    throw new StripeApiError(data?.error?.message ?? `Stripe checkout session creation failed (${response.status})`);
  }
  return { url: data.url };
}
