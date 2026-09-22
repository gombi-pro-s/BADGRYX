/**
 * Pure validation logic, deliberately kept free of the `server-only` import
 * that orchestrate.ts carries (see lib/mentor/prompt.ts vs.
 * lib/mentor/client.ts for the same split) -- this is what lets it be unit
 * tested directly instead of only indirectly through a live database.
 */

export interface ScanFileInput {
  filename: string;
  content: string;
}

export class ScanValidationError extends Error {}

export const MAX_FILES_PER_SCAN = 20;
// Matches the scan_files_content_bounded CHECK constraint in
// 20260922000002_security_scanner.sql -- kept in sync deliberately so a bad
// file is rejected here with a clear message instead of surfacing as a raw
// Postgres constraint violation.
export const MAX_FILE_BYTES = 300_000;

export function validateScanFiles(files: ScanFileInput[]): void {
  if (files.length === 0) {
    throw new ScanValidationError("At least one file is required.");
  }
  if (files.length > MAX_FILES_PER_SCAN) {
    throw new ScanValidationError(`A scan can include at most ${MAX_FILES_PER_SCAN} files (got ${files.length}).`);
  }
  for (const f of files) {
    if (Buffer.byteLength(f.content, "utf8") > MAX_FILE_BYTES) {
      throw new ScanValidationError(`${f.filename} exceeds the ${MAX_FILE_BYTES.toLocaleString()}-byte per-file limit.`);
    }
  }
}
