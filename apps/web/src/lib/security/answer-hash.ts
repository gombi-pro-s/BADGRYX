import "server-only";
import { createHash } from "node:crypto";

/**
 * Hashes an investigation's exact_text answer exactly the way the database
 * verifies it (`encode(digest(lower(trim(answer)), 'sha256'), 'hex')` in
 * supabase/migrations/20260922000009_investigations.sql) -- normalized
 * (trimmed, lowercased) then SHA-256, matching hashFlag's byte-identical
 * relationship to Postgres' digest() for the same input.
 *
 * server-only: the admin CMS must never send a plaintext answer to the
 * browser and hash it there -- hashing happens before the plaintext ever
 * leaves the server, and it is discarded after this call.
 */
export function hashInvestigationAnswer(plaintext: string): string {
  return createHash("sha256").update(plaintext.trim().toLowerCase(), "utf8").digest("hex");
}
