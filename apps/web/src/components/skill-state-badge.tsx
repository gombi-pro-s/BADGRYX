import type { SkillState } from "@/types/database";

const STATE_META: Record<SkillState, { label: string; className: string }> = {
  NOT_STARTED: { label: "Not started", className: "bg-background-subtle text-foreground-subtle border-border" },
  LEARNING: { label: "Learning", className: "bg-severity-low/10 text-severity-low border-severity-low/30" },
  PRACTICING: { label: "Practicing", className: "bg-warning-muted text-warning border-warning/30" },
  ASSESSED: { label: "Assessed", className: "bg-accent-muted text-accent border-accent/30" },
  DEMONSTRATED: { label: "Demonstrated", className: "bg-accent-muted text-accent border-accent/40" },
  MASTERED: { label: "Mastered", className: "bg-success-muted text-success border-success/30" },
  NEEDS_REVIEW: { label: "Needs review", className: "bg-danger-muted text-danger border-danger/30" },
};

export function SkillStateBadge({ state }: { state: SkillState }) {
  const meta = STATE_META[state];
  return (
    <span
      className={`inline-flex shrink-0 items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${meta.className}`}
    >
      {meta.label}
    </span>
  );
}
