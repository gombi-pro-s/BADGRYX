import type { ScanFindingStatus } from "@/types/database";

/**
 * Mirrors the legal transition graph enforced by
 * transition_scan_finding_status() (see
 * supabase/migrations/20260922000002_security_scanner.sql and
 * docs/adr/0008-scanner-finding-lifecycle.md). This copy exists only to
 * decide which buttons the UI offers -- the database re-validates every
 * transition server-side regardless of what this suggests, so a UI/DB
 * mismatch here would only ever show a wrong button, never allow an
 * illegal write.
 */
export const LEGAL_TRANSITIONS: Record<ScanFindingStatus, ScanFindingStatus[]> = {
  discovered: ["remediation_required", "false_positive", "wont_fix"],
  remediation_required: ["fix_applied", "false_positive", "wont_fix"],
  fix_applied: ["retested", "remediation_required"],
  retested: ["verified_fixed", "remediation_required"],
  false_positive: ["remediation_required"],
  wont_fix: ["remediation_required"],
  verified_fixed: ["remediation_required"],
};

export const STATUS_ACTION_LABELS: Record<ScanFindingStatus, string> = {
  discovered: "Mark discovered",
  remediation_required: "Mark remediation required",
  fix_applied: "Mark fix applied",
  retested: "Mark retested",
  verified_fixed: "Mark verified fixed",
  false_positive: "Mark false positive",
  wont_fix: "Mark won't fix",
};
