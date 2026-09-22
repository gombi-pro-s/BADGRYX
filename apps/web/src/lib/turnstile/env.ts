import "server-only";

/**
 * Typed getters for the Cloudflare Turnstile environment variables,
 * mirroring lib/billing/env.ts's fail-fast + isConfigured() pattern.
 * Neither var has a real value in this build environment (see
 * MANUAL_SETUP.md §8) -- isTurnstileConfigured() lets signUpAction() and
 * the signup page treat "not configured" as a normal, expected state
 * (skip the CAPTCHA entirely) rather than an unhandled exception.
 */
export function isTurnstileConfigured(): boolean {
  return Boolean(process.env.TURNSTILE_SECRET_KEY && process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY);
}

export function getTurnstileSecretKey(): string {
  const value = process.env.TURNSTILE_SECRET_KEY;
  if (!value) {
    throw new Error("Missing required environment variable TURNSTILE_SECRET_KEY. See .env.example / MANUAL_SETUP.md.");
  }
  return value;
}
