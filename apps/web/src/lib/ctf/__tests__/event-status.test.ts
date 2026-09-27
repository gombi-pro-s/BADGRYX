import { describe, expect, it } from "vitest";
import { ctfEventStatus } from "../event-status";

const NOW = new Date("2026-06-01T12:00:00Z").getTime();

describe("ctfEventStatus", () => {
  it("is upcoming when now is before starts_at", () => {
    expect(ctfEventStatus("2026-06-01T13:00:00Z", null, NOW)).toBe("upcoming");
  });

  it("is ended when now is at or after ends_at", () => {
    expect(ctfEventStatus(null, "2026-06-01T12:00:00Z", NOW)).toBe("ended");
    expect(ctfEventStatus(null, "2026-06-01T11:00:00Z", NOW)).toBe("ended");
  });

  it("is live when now is between starts_at and ends_at", () => {
    expect(ctfEventStatus("2026-06-01T11:00:00Z", "2026-06-01T13:00:00Z", NOW)).toBe("live");
  });

  it("is live with no bounds at all", () => {
    expect(ctfEventStatus(null, null, NOW)).toBe("live");
  });

  it("is live with only a past start and no end", () => {
    expect(ctfEventStatus("2026-06-01T11:00:00Z", null, NOW)).toBe("live");
  });

  it("is upcoming even with an end date, if the start hasn't arrived yet", () => {
    expect(ctfEventStatus("2026-06-02T00:00:00Z", "2026-06-03T00:00:00Z", NOW)).toBe("upcoming");
  });
});
