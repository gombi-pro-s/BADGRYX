"use client";

import { useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { SeverityBadge } from "@/components/severity-badge";
import { FindingStatusBadge } from "@/components/finding-status-badge";
import { LEGAL_TRANSITIONS, STATUS_ACTION_LABELS } from "@/lib/scanner/status-transitions";
import type {
  ScanFindingCategory,
  ScanFindingConfidence,
  ScanFindingSeverity,
  ScanFindingStatus,
  ScanFindingVerificationStatus,
  ReferenceLink,
} from "@/types/database";

export interface FindingCardData {
  id: string;
  file_id: string;
  rule_id: string;
  category: ScanFindingCategory;
  title: string;
  severity: ScanFindingSeverity;
  confidence: ScanFindingConfidence;
  line_start: number;
  line_end: number;
  evidence: string;
  explanation: string;
  impact: string;
  remediation: string;
  secure_example: string | null;
  reference_links: ReferenceLink[];
  verification_status: ScanFindingVerificationStatus;
  ai_enriched: boolean;
  status: ScanFindingStatus;
}

export function FindingCard({ finding: initialFinding, filename }: { finding: FindingCardData; filename: string }) {
  const [finding, setFinding] = useState(initialFinding);
  const [transitioning, setTransitioning] = useState<ScanFindingStatus | null>(null);
  const [enriching, setEnriching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);

  async function transition(newStatus: ScanFindingStatus) {
    setTransitioning(newStatus);
    setError(null);
    const supabase = createClient();
    const { data, error: rpcError } = await supabase.rpc("transition_scan_finding_status", {
      p_finding_id: finding.id,
      p_new_status: newStatus,
    });
    setTransitioning(null);
    if (rpcError || !data) {
      setError(rpcError?.message ?? "Could not update status.");
      return;
    }
    setFinding((prev) => ({ ...prev, status: data.status }));
  }

  async function enrich() {
    setEnriching(true);
    setError(null);
    try {
      const res = await fetch(`/api/scanner/findings/${finding.id}/enrich`, { method: "POST" });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? "Enrichment failed.");
      setFinding((prev) => ({
        ...prev,
        explanation: body.finding.explanation,
        impact: body.finding.impact,
        remediation: body.finding.remediation,
        secure_example: body.finding.secure_example,
        ai_enriched: true,
      }));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Enrichment failed.");
    } finally {
      setEnriching(false);
    }
  }

  const nextStatuses = LEGAL_TRANSITIONS[finding.status] ?? [];

  return (
    <div className="rounded-lg border border-border bg-surface p-5">
      <div className="mb-2 flex items-start justify-between gap-3">
        <div>
          <div className="mb-1 flex items-center gap-2">
            <SeverityBadge severity={finding.severity} />
            <FindingStatusBadge status={finding.status} />
            {finding.ai_enriched && <span className="text-xs text-foreground-subtle">AI-enriched</span>}
          </div>
          <h3 className="text-sm font-semibold text-foreground">{finding.title}</h3>
          <p className="text-xs text-foreground-subtle">
            {filename}:{finding.line_start}
            {finding.line_end !== finding.line_start ? `-${finding.line_end}` : ""} &middot; {finding.rule_id}
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-3">
          <Link
            href={`/mentor?contextType=finding&contextId=${finding.id}`}
            className="text-xs font-medium text-accent hover:underline"
          >
            Ask Mentor
          </Link>
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className="text-xs font-medium text-accent hover:underline"
          >
            {expanded ? "Collapse" : "Details"}
          </button>
        </div>
      </div>

      {expanded && (
        <div className="mt-4 space-y-3 border-t border-border pt-4 text-sm">
          <pre className="overflow-x-auto rounded-md bg-background-subtle p-3 font-mono text-xs text-foreground">
            {finding.evidence}
          </pre>
          <div>
            <h4 className="mb-1 text-xs font-semibold text-foreground-subtle uppercase">Explanation</h4>
            <p className="text-foreground-muted">{finding.explanation}</p>
          </div>
          <div>
            <h4 className="mb-1 text-xs font-semibold text-foreground-subtle uppercase">Impact</h4>
            <p className="text-foreground-muted">{finding.impact}</p>
          </div>
          <div>
            <h4 className="mb-1 text-xs font-semibold text-foreground-subtle uppercase">Remediation</h4>
            <p className="text-foreground-muted">{finding.remediation}</p>
          </div>
          {finding.secure_example && (
            <div>
              <h4 className="mb-1 text-xs font-semibold text-foreground-subtle uppercase">Secure example</h4>
              <pre className="overflow-x-auto rounded-md bg-background-subtle p-3 font-mono text-xs text-foreground">
                {finding.secure_example}
              </pre>
            </div>
          )}
          {finding.reference_links.length > 0 && (
            <div>
              <h4 className="mb-1 text-xs font-semibold text-foreground-subtle uppercase">References</h4>
              <ul className="list-inside list-disc text-foreground-muted">
                {finding.reference_links.map((ref) => (
                  <li key={ref.url}>
                    <a href={ref.url} target="_blank" rel="noreferrer" className="text-accent hover:underline">
                      {ref.title}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-2 border-t border-border pt-3">
            {nextStatuses.map((next) => (
              <button
                key={next}
                type="button"
                disabled={!!transitioning}
                onClick={() => transition(next)}
                className="rounded-md border border-border px-2.5 py-1 text-xs font-medium text-foreground-muted hover:border-border-strong hover:text-foreground disabled:opacity-50"
              >
                {transitioning === next ? "Updating..." : STATUS_ACTION_LABELS[next]}
              </button>
            ))}
            <Button type="button" variant="secondary" size="sm" disabled={enriching} onClick={enrich}>
              {enriching ? "Enriching..." : "Enrich with AI"}
            </Button>
          </div>
        </div>
      )}

      {error && (
        <p role="alert" className="mt-3 rounded-md border border-danger/30 bg-danger-muted px-3 py-2 text-sm text-danger">
          {error}
        </p>
      )}
    </div>
  );
}
