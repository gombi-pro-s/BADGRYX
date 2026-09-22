import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { checkScannerQuota } from "@/lib/scanner/rate-limit";
import { SeverityBadge } from "@/components/severity-badge";
import type { ScanFindingSeverity } from "@/types/database";
import { ScanUploader } from "./scan-uploader";

export const metadata: Metadata = { title: "Security Scanner" };

const SEVERITY_ORDER: ScanFindingSeverity[] = ["critical", "high", "medium", "low", "info"];

export default async function ScannerPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: scans }, quota] = await Promise.all([
    supabase
      .from("scans")
      .select("id, title, status, total_files, total_findings, findings_by_severity, created_at")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(20),
    checkScannerQuota(supabase, user.id),
  ]);

  const posture: Partial<Record<ScanFindingSeverity, number>> = {};
  for (const scan of scans ?? []) {
    for (const [severity, count] of Object.entries(scan.findings_by_severity)) {
      posture[severity as ScanFindingSeverity] = (posture[severity as ScanFindingSeverity] ?? 0) + count;
    }
  }
  const hasFindings = Object.values(posture).some((n) => (n ?? 0) > 0);

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <div className="mb-8 flex items-start justify-between gap-4">
        <div>
          <h1 className="mb-1 text-2xl font-semibold text-foreground">Security Scanner</h1>
          <p className="text-sm text-foreground-muted">
            Paste or upload source code for a deterministic static-analysis scan -- secrets, SQL injection, XSS,
            command injection, and more. A rule-based engine finds these, not an AI guessing -- see a finding&apos;s
            detail for what matched.
          </p>
        </div>
        <span className="shrink-0 text-xs text-foreground-subtle">{quota.used}/{quota.limit} scans today</span>
      </div>

      <ScanUploader />

      {scans && scans.length > 0 && (
        <div className="mt-10">
          <h2 className="mb-3 text-sm font-semibold text-foreground">
            Posture across your last {scans.length} scan{scans.length === 1 ? "" : "s"}
          </h2>
          <div className="flex flex-wrap items-center gap-2">
            {hasFindings ? (
              SEVERITY_ORDER.filter((sev) => (posture[sev] ?? 0) > 0).map((sev) => (
                <span
                  key={sev}
                  className="inline-flex items-center gap-1.5 rounded-full border border-border bg-surface px-3 py-1 text-xs"
                >
                  <SeverityBadge severity={sev} />
                  <span className="text-foreground-muted">{posture[sev]}</span>
                </span>
              ))
            ) : (
              <span className="text-sm text-foreground-subtle">No findings yet across these scans -- clean.</span>
            )}
          </div>
        </div>
      )}

      <h2 className="mt-10 mb-3 text-sm font-semibold text-foreground">Past scans</h2>
      {scans && scans.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {scans.map((scan) => (
            <li key={scan.id}>
              <Link
                href={`/scanner/${scan.id}`}
                className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
              >
                <div>
                  <p className="text-sm font-medium text-foreground">{scan.title}</p>
                  <p className="text-xs text-foreground-subtle">
                    {scan.total_files} file{scan.total_files === 1 ? "" : "s"} &middot; {scan.total_findings} finding
                    {scan.total_findings === 1 ? "" : "s"} &middot; {new Date(scan.created_at).toLocaleString()}
                  </p>
                </div>
                <span className="shrink-0 text-xs tracking-wide text-foreground-subtle uppercase">{scan.status}</span>
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No scans yet. Paste or upload code above to run your first scan.
        </div>
      )}
    </div>
  );
}
