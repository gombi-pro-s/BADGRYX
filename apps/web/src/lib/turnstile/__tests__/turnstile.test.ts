import { describe, expect, it } from "vitest";
import { buildTurnstileVerifyRequestBody, parseTurnstileVerifyResult } from "../turnstile";

describe("buildTurnstileVerifyRequestBody", () => {
  it("includes the secret and the response token", () => {
    const body = buildTurnstileVerifyRequestBody("secret_abc", "token_xyz");
    expect(body.get("secret")).toBe("secret_abc");
    expect(body.get("response")).toBe("token_xyz");
    expect(body.has("remoteip")).toBe(false);
  });

  it("includes remoteip when provided", () => {
    const body = buildTurnstileVerifyRequestBody("secret_abc", "token_xyz", "203.0.113.5");
    expect(body.get("remoteip")).toBe("203.0.113.5");
  });
});

describe("parseTurnstileVerifyResult", () => {
  it("accepts a real success response", () => {
    expect(parseTurnstileVerifyResult({ success: true, challenge_ts: "2026-01-01T00:00:00Z", hostname: "example.com" })).toBe(
      true,
    );
  });

  it("rejects an explicit failure response", () => {
    expect(parseTurnstileVerifyResult({ success: false, "error-codes": ["invalid-input-response"] })).toBe(false);
  });

  it("rejects null, non-object, and malformed responses rather than throwing", () => {
    expect(parseTurnstileVerifyResult(null)).toBe(false);
    expect(parseTurnstileVerifyResult(undefined)).toBe(false);
    expect(parseTurnstileVerifyResult("success")).toBe(false);
    expect(parseTurnstileVerifyResult(42)).toBe(false);
    expect(parseTurnstileVerifyResult({})).toBe(false);
  });

  it("rejects a response where success is truthy but not literally true", () => {
    expect(parseTurnstileVerifyResult({ success: "true" })).toBe(false);
    expect(parseTurnstileVerifyResult({ success: 1 })).toBe(false);
  });
});
