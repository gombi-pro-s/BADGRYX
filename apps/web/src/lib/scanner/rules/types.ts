import type {
  ReferenceLink,
  ScanFindingCategory,
  ScanFindingConfidence,
  ScanFindingSeverity,
  ScanFindingVerificationStatus,
} from "@/types/database";

/**
 * What a rule scans: the already-loaded file content, exactly as stored in
 * scan_files. `language` is a best-effort guess from the filename extension
 * (see detectLanguage in lib/scanner/language.ts) -- rules that only make
 * sense for certain languages use it to skip files they'd otherwise produce
 * noise on; rules that are language-agnostic (secrets, cleartext HTTP)
 * ignore it.
 */
export type ScanInputFile = {
  filename: string;
  language: string | null;
  content: string;
};

/** One match produced by a rule, before it's persisted as a scan_findings row. */
export type RuleMatch = {
  ruleId: string;
  category: ScanFindingCategory;
  title: string;
  severity: ScanFindingSeverity;
  confidence: ScanFindingConfidence;
  lineStart: number;
  lineEnd: number;
  evidence: string;
  explanation: string;
  impact: string;
  remediation: string;
  secureExample?: string;
  referenceLinks?: ReferenceLink[];
  verificationStatus: ScanFindingVerificationStatus;
};

export type ScanRule = {
  id: string;
  category: ScanFindingCategory;
  /** Undefined = applies to every file regardless of detected language. */
  languages?: string[];
  run(file: ScanInputFile): RuleMatch[];
};
