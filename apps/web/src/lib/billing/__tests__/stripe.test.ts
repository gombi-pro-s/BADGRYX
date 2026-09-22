import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildStripeCheckoutParams, verifyStripeSignature } from "../stripe";

const SECRET = "whsec_test_secret";

function sign(rawBody: string, timestampSeconds: number, secret = SECRET): string {
  const signature = createHmac("sha256", secret).update(`${timestampSeconds}.${rawBody}`).digest("hex");
  return `t=${timestampSeconds},v1=${signature}`;
}

describe("verifyStripeSignature", () => {
  it("accepts a correctly signed, fresh payload", () => {
    const rawBody = JSON.stringify({ id: "evt_1", type: "checkout.session.completed" });
    const now = 1_700_000_000_000;
    const header = sign(rawBody, Math.floor(now / 1000), SECRET);
    expect(verifyStripeSignature(rawBody, header, SECRET, { now })).toBe(true);
  });

  it("rejects a payload signed with the wrong secret", () => {
    const rawBody = JSON.stringify({ id: "evt_1" });
    const now = 1_700_000_000_000;
    const header = sign(rawBody, Math.floor(now / 1000), "wrong_secret");
    expect(verifyStripeSignature(rawBody, header, SECRET, { now })).toBe(false);
  });

  it("rejects a tampered body even with a validly formatted signature", () => {
    const originalBody = JSON.stringify({ id: "evt_1", amount: 100 });
    const now = 1_700_000_000_000;
    const header = sign(originalBody, Math.floor(now / 1000), SECRET);
    const tamperedBody = JSON.stringify({ id: "evt_1", amount: 999999 });
    expect(verifyStripeSignature(tamperedBody, header, SECRET, { now })).toBe(false);
  });

  it("rejects a signature older than the tolerance window (replay protection)", () => {
    const rawBody = JSON.stringify({ id: "evt_1" });
    const now = 1_700_000_000_000;
    const staleTimestamp = Math.floor(now / 1000) - 3600; // 1 hour old
    const header = sign(rawBody, staleTimestamp, SECRET);
    expect(verifyStripeSignature(rawBody, header, SECRET, { now, toleranceSeconds: 300 })).toBe(false);
  });

  it("rejects a malformed header", () => {
    expect(verifyStripeSignature("{}", "not-a-valid-header", SECRET)).toBe(false);
    expect(verifyStripeSignature("{}", "", SECRET)).toBe(false);
  });

  it("rejects a header missing the v1 signature", () => {
    expect(verifyStripeSignature("{}", "t=1700000000", SECRET)).toBe(false);
  });
});

describe("buildStripeCheckoutParams", () => {
  it("builds a subscription-mode checkout request carrying the internal user id", () => {
    const params = buildStripeCheckoutParams({
      priceId: "price_123",
      userId: "user-abc",
      userEmail: "alice@example.com",
      successUrl: "https://example.com/settings/billing?success=1",
      cancelUrl: "https://example.com/settings/billing?canceled=1",
    });
    expect(params.get("mode")).toBe("subscription");
    expect(params.get("line_items[0][price]")).toBe("price_123");
    expect(params.get("line_items[0][quantity]")).toBe("1");
    expect(params.get("client_reference_id")).toBe("user-abc");
    expect(params.get("customer_email")).toBe("alice@example.com");
    expect(params.get("success_url")).toContain("success=1");
  });
});
