import { describe, expect, it } from "vitest";
import { computePeriodEnd, PRO_PLAN_SLUG } from "../plans";

describe("PRO_PLAN_SLUG", () => {
  it("is 'pro'", () => {
    expect(PRO_PLAN_SLUG).toBe("pro");
  });
});

describe("computePeriodEnd", () => {
  it("adds one month for a monthly plan", () => {
    const from = new Date("2026-01-15T00:00:00Z");
    const end = computePeriodEnd("month", from);
    expect(end.toISOString()).toBe("2026-02-15T00:00:00.000Z");
  });

  it("adds one year for a yearly plan", () => {
    const from = new Date("2026-01-15T00:00:00Z");
    const end = computePeriodEnd("year", from);
    expect(end.toISOString()).toBe("2027-01-15T00:00:00.000Z");
  });

  it("rolls over year/month correctly at a December boundary", () => {
    const from = new Date("2026-12-20T00:00:00Z");
    const end = computePeriodEnd("month", from);
    expect(end.getUTCFullYear()).toBe(2027);
    expect(end.getUTCMonth()).toBe(0); // January
  });

  it("does not mutate the input date", () => {
    const from = new Date("2026-01-15T00:00:00Z");
    const original = from.toISOString();
    computePeriodEnd("month", from);
    expect(from.toISOString()).toBe(original);
  });
});
