import { describe, expect, it } from "vitest";
import { buildFlutterwavePaymentBody, verifyFlutterwaveSignature } from "../flutterwave";

const SECRET_HASH = "a-dashboard-configured-secret-hash";

describe("verifyFlutterwaveSignature", () => {
  it("accepts a header that exactly matches the configured secret hash", () => {
    expect(verifyFlutterwaveSignature(SECRET_HASH, SECRET_HASH)).toBe(true);
  });

  it("rejects a header that doesn't match", () => {
    expect(verifyFlutterwaveSignature("some-other-value", SECRET_HASH)).toBe(false);
  });

  it("rejects a missing/empty header", () => {
    expect(verifyFlutterwaveSignature("", SECRET_HASH)).toBe(false);
  });

  it("rejects a value that only differs in the last character (no length-based leak)", () => {
    expect(verifyFlutterwaveSignature(SECRET_HASH.slice(0, -1) + "x", SECRET_HASH)).toBe(false);
  });

  it("is not a prefix-match -- a longer string containing the secret is rejected", () => {
    expect(verifyFlutterwaveSignature(SECRET_HASH + "-extra", SECRET_HASH)).toBe(false);
  });
});

describe("buildFlutterwavePaymentBody", () => {
  it("carries the internal user id in meta and a unique tx_ref", () => {
    const body = buildFlutterwavePaymentBody({
      paymentPlanId: "plan_123",
      userId: "user-xyz",
      userEmail: "alice@example.com",
      amountUsd: 19,
      redirectUrl: "https://example.com/settings/billing",
    });
    expect(body.payment_plan).toBe("plan_123");
    expect(body.amount).toBe(19);
    expect((body.meta as { user_id: string }).user_id).toBe("user-xyz");
    expect(typeof body.tx_ref).toBe("string");
    expect((body.tx_ref as string).includes("user-xyz")).toBe(true);
  });
});
