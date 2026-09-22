import { timingSafeEqual, createHmac } from "node:crypto";

/**
 * Pure Stripe logic: signature verification and checkout-request building.
 * No network I/O, no `server-only` import, so this is unit-testable without
 * a real Stripe account -- mirrors lib/mentor/prompt.ts vs client.ts.
 */

/**
 * Verifies a `Stripe-Signature` header per Stripe's documented scheme:
 * header is `t=<unix-seconds>,v1=<hex-hmac>[,v1=<hex-hmac>...]`; the signed
 * payload is `${t}.${rawBody}`, HMAC-SHA256'd with the webhook secret. A
 * timestamp outside `toleranceSeconds` of `now` is rejected even with a
 * valid signature, to bound replay of an intercepted-but-old request.
 */
export function verifyStripeSignature(
  rawBody: string,
  signatureHeader: string,
  secret: string,
  options: { toleranceSeconds?: number; now?: number } = {},
): boolean {
  const toleranceSeconds = options.toleranceSeconds ?? 300;
  const now = options.now ?? Date.now();

  const parts = signatureHeader.split(",").map((p) => p.trim());
  let timestamp: string | null = null;
  const v1Signatures: string[] = [];
  for (const part of parts) {
    const [key, value] = part.split("=", 2);
    if (key === "t") timestamp = value;
    else if (key === "v1" && value) v1Signatures.push(value);
  }
  if (!timestamp || v1Signatures.length === 0) return false;

  const timestampSeconds = Number(timestamp);
  if (!Number.isFinite(timestampSeconds)) return false;
  if (Math.abs(now / 1000 - timestampSeconds) > toleranceSeconds) return false;

  const expected = createHmac("sha256", secret).update(`${timestamp}.${rawBody}`).digest("hex");
  const expectedBuf = Buffer.from(expected, "hex");

  return v1Signatures.some((sig) => {
    const sigBuf = Buffer.from(sig, "hex");
    return sigBuf.length === expectedBuf.length && timingSafeEqual(sigBuf, expectedBuf);
  });
}

export interface StripeCheckoutParams {
  priceId: string;
  userId: string;
  userEmail: string;
  successUrl: string;
  cancelUrl: string;
}

/**
 * Stripe's Checkout Sessions API takes a form-encoded body (including for
 * nested array params like line_items[0][price]) -- this builds exactly
 * that, with client_reference_id carrying our internal user id so the
 * webhook can attribute the resulting subscription without an extra
 * lookup.
 */
export function buildStripeCheckoutParams(params: StripeCheckoutParams): URLSearchParams {
  const body = new URLSearchParams();
  body.set("mode", "subscription");
  body.set("line_items[0][price]", params.priceId);
  body.set("line_items[0][quantity]", "1");
  body.set("success_url", params.successUrl);
  body.set("cancel_url", params.cancelUrl);
  body.set("client_reference_id", params.userId);
  body.set("customer_email", params.userEmail);
  return body;
}
