import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { FindingStatusBadge } from "../finding-status-badge";
import type { ScanFindingStatus } from "@/types/database";

const ALL_STATUSES: ScanFindingStatus[] = [
  "discovered",
  "remediation_required",
  "fix_applied",
  "retested",
  "verified_fixed",
  "false_positive",
  "wont_fix",
];

describe("FindingStatusBadge", () => {
  it.each(ALL_STATUSES)("renders a label for every finding status (%s)", (status) => {
    render(<FindingStatusBadge status={status} />);
    expect(screen.getByText(/./)).toBeInTheDocument();
  });

  it("renders a human-readable label for verified_fixed", () => {
    render(<FindingStatusBadge status="verified_fixed" />);
    expect(screen.getByText("Verified fixed")).toBeInTheDocument();
  });
});
