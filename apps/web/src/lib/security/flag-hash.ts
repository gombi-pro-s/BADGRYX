import "server-only";
import { createHash } from "node:crypto";

/**
 * Hashes a lab/CTF flag exactly the way the database verifies it
 * (`encode(digest(flag, 'sha256'), 'hex')` in
 * supabase/migrations/20260921000010_grading_and_evidence.sql) -- lowercase
 * hex SHA-256. Verified to produce byte-identical output to Postgres'
 * digest() for the same input during development.
 *
 * server-only: the admin CMS must never send a plaintext flag to the
 * browser and hash it there -- hashing happens in a Server Action before
 * the plaintext ever leaves the server, and the plaintext is discarded
 * after this call (never stored, never logged).
 */
export function hashFlag(plaintext: string): string {
  return createHash("sha256").update(plaintext, "utf8").digest("hex");
}
