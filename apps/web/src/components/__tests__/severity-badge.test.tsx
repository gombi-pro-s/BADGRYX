import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SeverityBadge } from "../severity-badge";
import type { ScanFindingSeverity } from "@/types/database";

const ALL_SEVERITIES: ScanFindingSeverity[] = ["critical", "high", "medium", "low", "info"];

describe("SeverityBadge", () => {
  it.each(ALL_SEVERITIES)("renders a label for every severity (%s)", (severity) => {
    render(<SeverityBadge severity={severity} />);
    expect(screen.getByText(/./)).toBeInTheDocument();
  });

  it("renders a human-readable label for critical", () => {
    render(<SeverityBadge severity="critical" />);
    expect(screen.getByText("Critical")).toBeInTheDocument();
  });
});
