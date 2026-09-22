"use server";

import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { logAuditEvent } from "@/lib/audit";

export interface DeleteAccountState {
  error: string | null;
}

export async function deleteMyAccountAction(
  _prev: DeleteAccountState,
  formData: FormData,
): Promise<DeleteAccountState> {
  const user = await requireUser();
  const confirmation = String(formData.get("confirmation") ?? "")
    .trim()
    .toLowerCase();

  if (!user.email || confirmation !== user.email.toLowerCase()) {
    return { error: "Type your account email exactly to confirm." };
  }

  const supabase = await createClient();
  // Logged while the session is still valid -- log_audit_event() stamps
  // actor_id = auth.uid() itself. The row survives the deletion below
  // (audit_log.actor_id is ON DELETE SET NULL, never CASCADE -- see
  // 20260922000018_account_deletion_fk_fixes.sql) as a permanent record
  // that this account existed and was deleted, even though the actor
  // reference itself goes to NULL a moment later.
  await logAuditEvent(supabase, "account.deleted", "user", user.id, null, { email: user.email });

  // Narrowly scoped to the caller's own, already-verified user id -- never
  // a caller-supplied id -- the same "server-side escalation only after
  // independent ownership verification" pattern as ADR 0009's terminal
  // execution engine. This is the one place in the app that calls the
  // GoTrue Admin API's deleteUser(): it's the only supported way to
  // actually remove a Supabase Auth user (a raw SQL DELETE would bypass
  // GoTrue's own internal bookkeeping).
  const admin = createAdminClient();
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) {
    return { error: error.message };
  }

  await supabase.auth.signOut();
  redirect("/login?deleted=1");
}
