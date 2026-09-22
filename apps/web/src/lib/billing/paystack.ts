import { timingSafeEqual, createHmac } from "node:crypto";

/**
 * Pure Paystack logic: signature verification and transaction-initialize
 * request building. No network I/O -- unit-testable without a real
 * Paystack account.
 */

/**
 * Verifies the `x-paystack-signature` header: hex(HMAC-SHA512(rawBody,
 * secretKey)). Unlike Stripe, Paystack signs with the same secret key used
 * for API calls -- there is no separate webhook-signing secret.
 */
export function verifyPaystackSignature(rawBody: string, signatureHeader: string, secretKey: string): boolean {
  if (!signatureHeader) return false;
  const expected = createHmac("sha512", secretKey).update(rawBody).digest("hex");
  const expectedBuf = Buffer.from(expected, "hex");
  const givenBuf = Buffer.from(signatureHeader, "hex");
  return givenBuf.length === expectedBuf.length && timingSafeEqual(givenBuf, expectedBuf);
}

export interface PaystackInitializeParams {
  planCode: string;
  userId: string;
  userEmail: string;
  callbackUrl: string;
}

/** Body for POST https://api.paystack.co/transaction/initialize. */
export function buildPaystackInitializeBody(params: PaystackInitializeParams): Record<string, unknown> {
  return {
    email: params.userEmail,
    plan: params.planCode,
    callback_url: params.callbackUrl,
    metadata: { user_id: params.userId },
  };
}
