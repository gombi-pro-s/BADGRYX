import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { FindingCard } from "./finding-card";

export const metadata: Metadata = { title: "Scan results" };

export default async function ScanDetailPage({ params }: { params: Promise<{ scanId: string }> }) {
  const { scanId } = await params;
  await requireUser();
  const supabase = await createClient();

  const { data: scan } = await supabase
    .from("scans")
    .select("id, title, status, total_files, total_findings, error_message, created_at")
    .eq("id", scanId)
    .maybeSingle();
  if (!scan) notFound();

  const [{ data: findings }, { data: files }] = await Promise.all([
    supabase
      .from("scan_findings")
      .select(
        "id, file_id, rule_id, category, title, severity, confidence, line_start, line_end, evidence, explanation, impact, remediation, secure_example, reference_links, verification_status, ai_enriched, status",
      )
      .eq("scan_id", scanId)
      // Postgres orders an enum by its declared value order -- scan_finding_severity
      // was declared ('critical','high','medium','low','info'), so this ascending
      // sort already puts the most severe findings first.
      .order("severity", { ascending: true })
      .order("line_start", { ascending: true }),
    supabase.from("scan_files").select("id, filename").eq("scan_id", scanId),
  ]);

  const filenameById = new Map((files ?? []).map((f) => [f.id, f.filename]));

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <Link href="/scanner" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; All scans
      </Link>

      <div className="mb-6">
        <h1 className="mb-1 text-xl font-semibold text-foreground">{scan.title}</h1>
        <p className="text-sm text-foreground-muted">
          {scan.total_files} file{scan.total_files === 1 ? "" : "s"} scanned &middot;{" "}
          {new Date(scan.created_at).toLocaleString()} &middot; {scan.status}
        </p>
      </div>

      {scan.status === "failed" && (
        <div className="mb-6 rounded-md border border-danger/30 bg-danger-muted px-4 py-3 text-sm text-danger">
          Scan failed: {scan.error_message ?? "Unknown error."}
        </div>
      )}

      {!findings || findings.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          {scan.status === "completed"
            ? "No findings -- the deterministic rule engine found nothing to flag in this scan."
            : "This scan has no findings yet."}
        </div>
      ) : (
        <div className="space-y-4">
          {findings.map((finding) => (
            <FindingCard key={finding.id} finding={finding} filename={filenameById.get(finding.file_id) ?? "unknown file"} />
          ))}
        </div>
      )}
    </div>
  );
}
