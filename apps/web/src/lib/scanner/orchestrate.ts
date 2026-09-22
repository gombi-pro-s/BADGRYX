import "server-only";

import { createHash } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, ScanTargetType } from "@/types/database";
import { runRulesOnFile } from "./rules";
import { detectLanguage } from "./language";
import { validateScanFiles, type ScanFileInput } from "./validate";

export type { ScanFileInput };
export { ScanValidationError } from "./validate";

export interface ScanResult {
  scanId: string;
  totalFiles: number;
  totalFindings: number;
}

/**
 * Runs the deterministic rule engine (lib/scanner/rules) over every file and
 * persists the scan/files/findings via the CALLER'S OWN session -- this
 * function takes a user-scoped Supabase client, not a service-role one, so
 * every write still goes through the RLS policies in
 * 20260922000002_security_scanner.sql (scans_insert_own,
 * scan_files_insert_own, scan_findings_insert_own). There is no privileged
 * bypass here: the orchestrator can only ever write scans/findings the
 * calling user is already allowed to own.
 */
export async function runScan(
  supabase: SupabaseClient<Database>,
  userId: string,
  title: string,
  targetType: ScanTargetType,
  files: ScanFileInput[],
): Promise<ScanResult> {
  validateScanFiles(files);

  const { data: scan, error: scanError } = await supabase
    .from("scans")
    .insert({
      user_id: userId,
      title,
      target_type: targetType,
      status: "running",
      started_at: new Date().toISOString(),
    })
    .select("id")
    .single();
  if (scanError || !scan) {
    throw new Error(`Failed to create scan: ${scanError?.message ?? "unknown error"}`);
  }

  try {
    for (const file of files) {
      const language = detectLanguage(file.filename);

      const { data: fileRow, error: fileError } = await supabase
        .from("scan_files")
        .insert({
          scan_id: scan.id,
          filename: file.filename,
          language,
          content: file.content,
          size_bytes: Buffer.byteLength(file.content, "utf8"),
          content_sha256: createHash("sha256").update(file.content, "utf8").digest("hex"),
        })
        .select("id")
        .single();
      if (fileError || !fileRow) {
        throw new Error(`Failed to store ${file.filename}: ${fileError?.message ?? "unknown error"}`);
      }

      const matches = runRulesOnFile({ filename: file.filename, language, content: file.content });
      if (matches.length === 0) continue;

      const { error: findingsError } = await supabase.from("scan_findings").insert(
        matches.map((m) => ({
          scan_id: scan.id,
          file_id: fileRow.id,
          rule_id: m.ruleId,
          category: m.category,
          title: m.title,
          severity: m.severity,
          confidence: m.confidence,
          line_start: m.lineStart,
          line_end: m.lineEnd,
          evidence: m.evidence,
          explanation: m.explanation,
          impact: m.impact,
          remediation: m.remediation,
          secure_example: m.secureExample ?? null,
          reference_links: m.referenceLinks ?? [],
          verification_status: m.verificationStatus,
        })),
      );
      if (findingsError) {
        throw new Error(`Failed to store findings for ${file.filename}: ${findingsError.message}`);
      }
    }

    const { data: completed, error: completeError } = await supabase
      .from("scans")
      .update({ status: "completed", completed_at: new Date().toISOString() })
      .eq("id", scan.id)
      .select("total_files, total_findings")
      .single();
    if (completeError || !completed) {
      throw new Error(`Failed to finalize scan: ${completeError?.message ?? "unknown error"}`);
    }

    return { scanId: scan.id, totalFiles: completed.total_files, totalFindings: completed.total_findings };
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    await supabase
      .from("scans")
      .update({ status: "failed", error_message: message, completed_at: new Date().toISOString() })
      .eq("id", scan.id);
    throw err;
  }
}
