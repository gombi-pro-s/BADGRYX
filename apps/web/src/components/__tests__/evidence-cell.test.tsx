import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { EvidenceCell } from "../evidence-cell";
import type { SkillEvidenceOutcome } from "@/types/database";

const ALL_OUTCOMES: SkillEvidenceOutcome[] = ["passed", "partial", "failed"];

describe("EvidenceCell", () => {
  it.each(ALL_OUTCOMES)("renders a titled indicator for every outcome (%s)", (outcome) => {
    render(<EvidenceCell outcome={outcome} label="Quiz" />);
    expect(screen.getByTitle(`Quiz: ${outcome === "passed" ? "passed" : outcome}`)).toBeInTheDocument();
  });

  it("renders a dash for a never-attempted type, not a false negative", () => {
    render(<EvidenceCell outcome={null} label="CTF" />);
    expect(screen.getByTitle("CTF: not attempted")).toBeInTheDocument();
    expect(screen.getByText("–")).toBeInTheDocument();
  });

  it("distinguishes passed from failed visually, not just by title text", () => {
    const { container: passedContainer } = render(<EvidenceCell outcome="passed" label="Quiz" />);
    const { container: failedContainer } = render(<EvidenceCell outcome="failed" label="Quiz" />);
    expect(passedContainer.querySelector("span")?.className).not.toEqual(
      failedContainer.querySelector("span")?.className,
    );
  });
});
