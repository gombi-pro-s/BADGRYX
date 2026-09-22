import "server-only";

import { buildFlutterwavePaymentBody, type FlutterwavePaymentParams } from "./flutterwave";
import { getFlutterwaveSecretKey } from "./env";

export class FlutterwaveApiError extends Error {}

/** Creates a real Flutterwave payment and returns its hosted payment link. */
export async function createFlutterwavePayment(params: FlutterwavePaymentParams): Promise<{ url: string }> {
  const response = await fetch("https://api.flutterwave.com/v3/payments", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getFlutterwaveSecretKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(buildFlutterwavePaymentBody(params)),
  });

  const data = await response.json().catch(() => null);
  if (!response.ok || data?.status !== "success" || !data?.data?.link) {
    throw new FlutterwaveApiError(data?.message ?? `Flutterwave payment creation failed (${response.status})`);
  }
  return { url: data.data.link };
}
