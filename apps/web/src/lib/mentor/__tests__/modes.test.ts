import { describe, expect, it } from "vitest";
import { ALL_MENTOR_MODES, GENERAL_MODES, MODE_LABELS, defaultModeForContext, extraModesForContext } from "../modes";
import type { MentorContextType } from "@/types/database";

// Not imported from lib/mentor/context.ts's own ALL_MENTOR_CONTEXT_TYPES:
// that file has `import "server-only"`, which throws unconditionally
// outside a server bundler context -- including under vitest, the same
// reason context.ts itself has no direct unit tests (see AUDIT-009's
// "fixed structurally instead of tested" note). This local list is the
// type's own literal union, restated for the test only.
const ALL_CONTEXT_TYPES: MentorContextType[] = [
  "skill",
  "lesson",
  "lab",
  "ctf",
  "investigation",
  "finding",
  "report",
  "general",
];

describe("defaultModeForContext", () => {
  it("defaults finding to explain_finding, not the generic explain", () => {
    expect(defaultModeForContext("finding")).toBe("explain_finding");
  });

  it("defaults investigation to guide_investigation", () => {
    expect(defaultModeForContext("investigation")).toBe("guide_investigation");
  });

  it("defaults report to review_report", () => {
    expect(defaultModeForContext("report")).toBe("review_report");
  });

  it("defaults lesson to teach, lab/ctf to hint", () => {
    expect(defaultModeForContext("lesson")).toBe("teach");
    expect(defaultModeForContext("lab")).toBe("hint");
    expect(defaultModeForContext("ctf")).toBe("hint");
  });

  it("defaults skill and general to explain", () => {
    expect(defaultModeForContext("skill")).toBe("explain");
    expect(defaultModeForContext("general")).toBe("explain");
  });

  it("returns a mode from ALL_MENTOR_MODES for every context type this app defines", () => {
    for (const contextType of ALL_CONTEXT_TYPES) {
      expect(ALL_MENTOR_MODES).toContain(defaultModeForContext(contextType));
    }
  });
});

describe("extraModesForContext", () => {
  it("offers no extra pills for contexts with no dedicated mode", () => {
    expect(extraModesForContext("skill")).toEqual([]);
    expect(extraModesForContext("lesson")).toEqual([]);
    expect(extraModesForContext("general")).toEqual([]);
  });

  it("offers both review modes for report, since either can apply", () => {
    expect(extraModesForContext("report")).toEqual(["review_report", "review_methodology"]);
  });

  it("every extra mode offered is a real MentorMode", () => {
    for (const contextType of ALL_CONTEXT_TYPES) {
      for (const mode of extraModesForContext(contextType)) {
        expect(ALL_MENTOR_MODES).toContain(mode);
      }
    }
  });
});

describe("MODE_LABELS", () => {
  it("has a label for every mode in ALL_MENTOR_MODES", () => {
    for (const mode of ALL_MENTOR_MODES) {
      expect(MODE_LABELS[mode]).toBeTruthy();
    }
  });
});

describe("GENERAL_MODES", () => {
  it("is a subset of ALL_MENTOR_MODES", () => {
    for (const mode of GENERAL_MODES) {
      expect(ALL_MENTOR_MODES).toContain(mode);
    }
  });
});
