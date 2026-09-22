import "server-only";

import { buildTurnstileVerifyRequestBody, parseTurnstileVerifyResult } from "./turnstile";
import { getTurnstileSecretKey } from "./env";

const VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";

/**
 * Verifies a Turnstile token against Cloudflare's siteverify endpoint.
 * Never throws on a failed/network-error verification -- a bad token or an
 * unreachable Cloudflare should both simply fail the CAPTCHA check (the
 * caller shows "verification failed, try again"), not crash the signup
 * request with a 500.
 */
export async function verifyTurnstileToken(token: string, remoteIp?: string): Promise<boolean> {
  if (!token) return false;

  const body = buildTurnstileVerifyRequestBody(getTurnstileSecretKey(), token, remoteIp);

  try {
    const response = await fetch(VERIFY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: body.toString(),
    });
    const data = await response.json().catch(() => null);
    return parseTurnstileVerifyResult(data);
  } catch {
    return false;
  }
}
