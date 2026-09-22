import { describe, expect, it } from "vitest";
import { LEGAL_TRANSITIONS, STATUS_ACTION_LABELS } from "../status-transitions";
import type { ScanFindingStatus } from "@/types/database";

// The exact edge set transition_scan_finding_status() accepts (see
// supabase/migrations/20260922000002_security_scanner.sql and
// supabase/tests/007_scanner_rls.sql) -- kept here so a change to one side
// without the other fails a test instead of silently drifting.
const EXPECTED_EDGES: [ScanFindingStatus, ScanFindingStatus][] = [
  ["discovered", "remediation_required"],
  ["discovered", "false_positive"],
  ["discovered", "wont_fix"],
  ["remediation_required", "fix_applied"],
  ["remediation_required", "false_positive"],
  ["remediation_required", "wont_fix"],
  ["fix_applied", "retested"],
  ["fix_applied", "remediation_required"],
  ["retested", "verified_fixed"],
  ["retested", "remediation_required"],
  ["false_positive", "remediation_required"],
  ["wont_fix", "remediation_required"],
  ["verified_fixed", "remediation_required"],
];

describe("LEGAL_TRANSITIONS", () => {
  it("matches the exact edge set the database function accepts", () => {
    const actualEdges = Object.entries(LEGAL_TRANSITIONS).flatMap(([from, tos]) =>
      tos.map((to) => [from, to] as [ScanFindingStatus, ScanFindingStatus]),
    );
    expect(actualEdges.sort()).toEqual([...EXPECTED_EDGES].sort());
  });

  it("has no self-loops (re-asserting the same status is a no-op handled separately, not a transition)", () => {
    for (const [from, tos] of Object.entries(LEGAL_TRANSITIONS)) {
      expect(tos).not.toContain(from);
    }
  });

  it("has a UI label for every status", () => {
    for (const status of Object.keys(LEGAL_TRANSITIONS) as ScanFindingStatus[]) {
      expect(STATUS_ACTION_LABELS[status]).toBeTruthy();
    }
  });
});
