import "server-only";

import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { getSupabaseServiceRoleKey, getSupabaseUrl } from "./env";

/**
 * service_role Supabase client. BYPASSES ROW LEVEL SECURITY ENTIRELY.
 *
 * The `server-only` import makes any accidental client-bundle import of this
 * file a build-time error rather than a runtime secret leak. Use this only
 * for code that has already independently verified the caller's authority
 * to perform the operation (e.g. a webhook handler verified by provider
 * signature, an admin-only Server Action that re-checks the caller's role).
 * Never construct this client per-request from user input.
 */
export function createAdminClient() {
  return createSupabaseClient<Database>(getSupabaseUrl(), getSupabaseServiceRoleKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
}
