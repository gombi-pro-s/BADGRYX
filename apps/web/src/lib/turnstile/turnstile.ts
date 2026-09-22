/**
 * Pure Cloudflare Turnstile logic: request-building and response-parsing.
 * No network I/O, no `server-only` import, so this is unit-testable without
 * a real Cloudflare account -- mirrors lib/billing/stripe.ts vs
 * stripe-client.ts.
 */

/**
 * Cloudflare's siteverify endpoint takes a form-encoded body: the secret
 * key, the token the widget produced client-side (field name
 * "cf-turnstile-response" on the form), and optionally the caller's IP
 * (improves Cloudflare's own scoring, not required for verification to
 * work).
 */
export function buildTurnstileVerifyRequestBody(secret: string, token: string, remoteIp?: string): URLSearchParams {
  const body = new URLSearchParams();
  body.set("secret", secret);
  body.set("response", token);
  if (remoteIp) body.set("remoteip", remoteIp);
  return body;
}

export interface TurnstileVerifyResponse {
  success: boolean;
  "error-codes"?: string[];
}

/**
 * Cloudflare's response is `{ success: boolean, ... }`. Anything that
 * doesn't parse as that shape is treated as a failure, not an exception --
 * a malformed/unexpected response from Cloudflare should block the signup
 * the same way an explicit `success: false` would, never silently pass it.
 */
export function parseTurnstileVerifyResult(json: unknown): boolean {
  if (typeof json !== "object" || json === null) return false;
  const record = json as Record<string, unknown>;
  return record.success === true;
}
