import type { SkillEvidenceOutcome } from "@/types/database";

const OUTCOME_META: Record<SkillEvidenceOutcome, { symbol: string; className: string; label: string }> = {
  passed: { symbol: "✓", className: "bg-success-muted text-success", label: "Passed" },
  partial: { symbol: "~", className: "bg-warning-muted text-warning", label: "Partial" },
  failed: { symbol: "✗", className: "bg-danger-muted text-danger", label: "Failed" },
};

/**
 * One cell of the "Prove Your Skill" matrix: the best real outcome recorded
 * for a given (skill, evidence_type) pair, or a plain dash if that type of
 * evidence has never been attempted for this skill.
 */
export function EvidenceCell({ outcome, label }: { outcome: SkillEvidenceOutcome | null; label: string }) {
  if (!outcome) {
    return (
      <span
        title={`${label}: not attempted`}
        className="inline-flex h-6 w-6 items-center justify-center rounded-full text-foreground-subtle"
      >
        &ndash;
      </span>
    );
  }
  const meta = OUTCOME_META[outcome];
  return (
    <span
      title={`${label}: ${meta.label.toLowerCase()}`}
      className={`inline-flex h-6 w-6 items-center justify-center rounded-full text-xs font-semibold ${meta.className}`}
    >
      {meta.symbol}
    </span>
  );
}
