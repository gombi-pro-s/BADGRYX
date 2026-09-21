import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { SkillStateBadge } from "../skill-state-badge";
import type { SkillState } from "@/types/database";

const ALL_STATES: SkillState[] = [
  "NOT_STARTED",
  "LEARNING",
  "PRACTICING",
  "ASSESSED",
  "DEMONSTRATED",
  "MASTERED",
  "NEEDS_REVIEW",
];

describe("SkillStateBadge", () => {
  it.each(ALL_STATES)("renders a label for every skill state (%s)", (state) => {
    render(<SkillStateBadge state={state} />);
    expect(screen.getByText(/./)).toBeInTheDocument();
  });

  it("renders a human-readable label for MASTERED", () => {
    render(<SkillStateBadge state="MASTERED" />);
    expect(screen.getByText("Mastered")).toBeInTheDocument();
  });

  it("renders a human-readable label for NEEDS_REVIEW", () => {
    render(<SkillStateBadge state="NEEDS_REVIEW" />);
    expect(screen.getByText("Needs review")).toBeInTheDocument();
  });
});
