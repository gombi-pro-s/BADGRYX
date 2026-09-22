import type { ScanFindingSeverity } from "@/types/database";

const SEVERITY_META: Record<ScanFindingSeverity, { label: string; className: string }> = {
  critical: { label: "Critical", className: "bg-severity-critical/10 text-severity-critical border-severity-critical/30" },
  high: { label: "High", className: "bg-severity-high/10 text-severity-high border-severity-high/30" },
  medium: { label: "Medium", className: "bg-severity-medium/10 text-severity-medium border-severity-medium/30" },
  low: { label: "Low", className: "bg-severity-low/10 text-severity-low border-severity-low/30" },
  info: { label: "Info", className: "bg-severity-info/10 text-severity-info border-severity-info/30" },
};

export function SeverityBadge({ severity }: { severity: ScanFindingSeverity }) {
  const meta = SEVERITY_META[severity];
  return (
    <span
      className={`inline-flex shrink-0 items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${meta.className}`}
    >
      {meta.label}
    </span>
  );
}
