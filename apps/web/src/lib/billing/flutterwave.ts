import { timingSafeEqual } from "node:crypto";

/**
 * Pure Flutterwave logic: signature verification and payment-request
 * building. No network I/O -- unit-testable without a real Flutterwave
 * account.
 */

/**
 * Verifies the `verif-hash` header. Unlike Stripe/Paystack, Flutterwave's
 * webhook "signature" is NOT an HMAC of the payload -- it's a shared secret
 * string you set in their dashboard, echoed back verbatim on every webhook
 * call. Verification is therefore a constant-time string comparison, not a
 * digest computation.
 */
export function verifyFlutterwaveSignature(headerValue: string, expectedSecretHash: string): boolean {
  if (!headerValue) return false;
  const headerBuf = Buffer.from(headerValue, "utf8");
  const expectedBuf = Buffer.from(expectedSecretHash, "utf8");
  return headerBuf.length === expectedBuf.length && timingSafeEqual(headerBuf, expectedBuf);
}

export interface FlutterwavePaymentParams {
  paymentPlanId: string;
  userId: string;
  userEmail: string;
  amountUsd: number;
  redirectUrl: string;
}

/** Body for POST https://api.flutterwave.com/v3/payments. */
export function buildFlutterwavePaymentBody(params: FlutterwavePaymentParams): Record<string, unknown> {
  return {
    tx_ref: `icorepen-pro-${params.userId}-${Date.now()}`,
    amount: params.amountUsd,
    currency: "USD",
    redirect_url: params.redirectUrl,
    payment_plan: params.paymentPlanId,
    customer: { email: params.userEmail },
    meta: { user_id: params.userId },
  };
}
