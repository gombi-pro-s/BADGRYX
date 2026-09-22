import "server-only";

import { buildPaystackInitializeBody, type PaystackInitializeParams } from "./paystack";
import { getPaystackSecretKey } from "./env";

export class PaystackApiError extends Error {}

/** Creates a real Paystack transaction and returns its hosted authorization URL. */
export async function createPaystackTransaction(params: PaystackInitializeParams): Promise<{ url: string }> {
  const response = await fetch("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getPaystackSecretKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(buildPaystackInitializeBody(params)),
  });

  const data = await response.json().catch(() => null);
  if (!response.ok || !data?.status || !data?.data?.authorization_url) {
    throw new PaystackApiError(data?.message ?? `Paystack transaction initialize failed (${response.status})`);
  }
  return { url: data.data.authorization_url };
}
