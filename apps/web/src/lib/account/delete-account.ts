import "server-only";

import type { SupabaseClient, User } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { logAuditEvent } from "@/lib/audit";
import { createAdminClient } from "@/lib/supabase/admin";
import { confirmsAccountDeletion } from "./confirm-deletion";

export interface DeleteAccountResult {
  error: string | null;
}

/**
 * Permanently deletes the given user's Supabase Auth account -- the
 * shared core of `settings/privacy/actions.ts`'s `deleteMyAccountAction`
 * (the web form) and `/api/account/delete` (the mobile Route Handler,
 * see ADR 0033/0067), extracted so this is never hand-ported a second
 * time in Dart. Neither caller gets a redirect from here: that's a
 * Next.js Server Action/page concept a Route Handler has no equivalent
 * of, so each caller navigates its own way after a successful result.
 */
export async function deleteAccount(
  supabase: SupabaseClient<Database>,
  user: User,
  confirmation: string,
): Promise<DeleteAccountResult> {
  if (!confirmsAccountDeletion(confirmation, user.email)) {
    return { error: "Type your account email exactly to confirm." };
  }

  // Logged while the session is still valid -- log_audit_event() stamps
  // actor_id = auth.uid() itself. The row survives the deletion below
  // (audit_log.actor_id is ON DELETE SET NULL, never CASCADE -- see
  // 20260922000018_account_deletion_fk_fixes.sql) as a permanent record
  // that this account existed and was deleted, even though the actor
  // reference itself goes to NULL a moment later.
  await logAuditEvent(supabase, "account.deleted", "user", user.id, null, { email: user.email });

  // Narrowly scoped to the caller's own, already-verified user id --
  // never a caller-supplied id -- the same "server-side escalation only
  // after independent ownership verification" pattern as ADR 0009's
  // terminal execution engine. This is the one place in the app that
  // calls the GoTrue Admin API's deleteUser(): it's the only supported
  // way to actually remove a Supabase Auth user (a raw SQL DELETE would
  // bypass GoTrue's own internal bookkeeping).
  const admin = createAdminClient();
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) {
    return { error: error.message };
  }

  return { error: null };
}
