import type { ScanFindingStatus } from "@/types/database";

const STATUS_META: Record<ScanFindingStatus, { label: string; className: string }> = {
  discovered: { label: "Discovered", className: "bg-background-subtle text-foreground-subtle border-border" },
  remediation_required: { label: "Remediation required", className: "bg-warning-muted text-warning border-warning/30" },
  fix_applied: { label: "Fix applied", className: "bg-accent-muted text-accent border-accent/30" },
  retested: { label: "Retested", className: "bg-accent-muted text-accent border-accent/40" },
  verified_fixed: { label: "Verified fixed", className: "bg-success-muted text-success border-success/30" },
  false_positive: { label: "False positive", className: "bg-background-subtle text-foreground-subtle border-border" },
  wont_fix: { label: "Won't fix", className: "bg-background-subtle text-foreground-subtle border-border" },
};

export function FindingStatusBadge({ status }: { status: ScanFindingStatus }) {
  const meta = STATUS_META[status];
  return (
    <span
      className={`inline-flex shrink-0 items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${meta.className}`}
    >
      {meta.label}
    </span>
  );
}
