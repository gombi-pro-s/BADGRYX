import "server-only";

/**
 * Typed getters for the payment-provider environment variables, mirroring
 * lib/env.ts's fail-fast pattern (a missing var throws a clear message
 * instead of surfacing as a confusing error deep in a fetch call). None of
 * these have real values in this build environment -- see ADR 0005 and
 * MANUAL_SETUP.md. The is*Configured() helpers let callers (checkout
 * actions) check before attempting a call and report "not configured yet"
 * as a normal, expected UI state rather than an unhandled exception.
 */

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}. See .env.example / MANUAL_SETUP.md.`);
  }
  return value;
}

// ---- Stripe -----------------------------------------------------------------

export function isStripeConfigured(): boolean {
  return Boolean(process.env.STRIPE_SECRET_KEY && process.env.STRIPE_WEBHOOK_SECRET && process.env.STRIPE_PRICE_ID_PRO);
}
export function getStripeSecretKey(): string {
  return requireEnv("STRIPE_SECRET_KEY");
}
export function getStripeWebhookSecret(): string {
  return requireEnv("STRIPE_WEBHOOK_SECRET");
}
export function getStripePriceIdPro(): string {
  return requireEnv("STRIPE_PRICE_ID_PRO");
}

// ---- Paystack -----------------------------------------------------------------
// Paystack signs webhooks with the same secret key used for API calls --
// there is no separate webhook-signing secret, unlike Stripe.

export function isPaystackConfigured(): boolean {
  return Boolean(process.env.PAYSTACK_SECRET_KEY && process.env.PAYSTACK_PLAN_CODE_PRO);
}
export function getPaystackSecretKey(): string {
  return requireEnv("PAYSTACK_SECRET_KEY");
}
export function getPaystackPlanCodePro(): string {
  return requireEnv("PAYSTACK_PLAN_CODE_PRO");
}

// ---- Flutterwave --------------------------------------------------------------
// Flutterwave's webhook "signature" is a shared secret hash you configure in
// their dashboard, echoed back verbatim in the verif-hash header -- not an
// HMAC of the payload like Stripe/Paystack. See flutterwave.ts.

export function isFlutterwaveConfigured(): boolean {
  return Boolean(
    process.env.FLUTTERWAVE_SECRET_KEY &&
      process.env.FLUTTERWAVE_WEBHOOK_SECRET_HASH &&
      process.env.FLUTTERWAVE_PAYMENT_PLAN_ID_PRO,
  );
}
export function getFlutterwaveSecretKey(): string {
  return requireEnv("FLUTTERWAVE_SECRET_KEY");
}
export function getFlutterwaveWebhookSecretHash(): string {
  return requireEnv("FLUTTERWAVE_WEBHOOK_SECRET_HASH");
}
export function getFlutterwavePaymentPlanIdPro(): string {
  return requireEnv("FLUTTERWAVE_PAYMENT_PLAN_ID_PRO");
}
