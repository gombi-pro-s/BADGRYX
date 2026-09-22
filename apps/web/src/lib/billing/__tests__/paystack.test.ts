import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildPaystackInitializeBody, verifyPaystackSignature } from "../paystack";

const SECRET_KEY = "sk_test_paystack_secret";

function sign(rawBody: string, secretKey = SECRET_KEY): string {
  return createHmac("sha512", secretKey).update(rawBody).digest("hex");
}

describe("verifyPaystackSignature", () => {
  it("accepts a correctly signed payload", () => {
    const rawBody = JSON.stringify({ event: "charge.success", data: { reference: "ref_1" } });
    expect(verifyPaystackSignature(rawBody, sign(rawBody), SECRET_KEY)).toBe(true);
  });

  it("rejects a payload signed with the wrong secret key", () => {
    const rawBody = JSON.stringify({ event: "charge.success" });
    expect(verifyPaystackSignature(rawBody, sign(rawBody, "wrong_key"), SECRET_KEY)).toBe(false);
  });

  it("rejects a tampered body", () => {
    const originalBody = JSON.stringify({ event: "charge.success", data: { amount: 100 } });
    const signature = sign(originalBody);
    const tamperedBody = JSON.stringify({ event: "charge.success", data: { amount: 999999 } });
    expect(verifyPaystackSignature(tamperedBody, signature, SECRET_KEY)).toBe(false);
  });

  it("rejects an empty or missing signature header", () => {
    expect(verifyPaystackSignature("{}", "", SECRET_KEY)).toBe(false);
  });

  it("rejects a non-hex garbage signature without throwing", () => {
    expect(() => verifyPaystackSignature("{}", "not-hex-at-all!!", SECRET_KEY)).not.toThrow();
    expect(verifyPaystackSignature("{}", "not-hex-at-all!!", SECRET_KEY)).toBe(false);
  });
});

describe("buildPaystackInitializeBody", () => {
  it("carries the internal user id in metadata and the plan code", () => {
    const body = buildPaystackInitializeBody({
      planCode: "PLN_abc123",
      userId: "user-xyz",
      userEmail: "alice@example.com",
      callbackUrl: "https://example.com/settings/billing",
    });
    expect(body.plan).toBe("PLN_abc123");
    expect(body.email).toBe("alice@example.com");
    expect((body.metadata as { user_id: string }).user_id).toBe("user-xyz");
  });
});
