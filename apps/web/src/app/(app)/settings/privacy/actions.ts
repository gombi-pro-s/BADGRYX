"use server";

import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { deleteAccount } from "@/lib/account/delete-account";

export interface DeleteAccountState {
  error: string | null;
}

/**
 * The actual deletion logic lives in `deleteAccount()`
 * (lib/account/delete-account.ts), shared with the mobile-facing
 * `/api/account/delete` Route Handler -- this action is just the
 * FormData adapter around it, plus the sign-out + redirect a Route
 * Handler has no equivalent of. See ADR 0067.
 */
export async function deleteMyAccountAction(
  _prev: DeleteAccountState,
  formData: FormData,
): Promise<DeleteAccountState> {
  const user = await requireUser();
  const confirmation = String(formData.get("confirmation") ?? "");

  const supabase = await createClient();
  const result = await deleteAccount(supabase, user, confirmation);
  if (result.error) {
    return { error: result.error };
  }

  await supabase.auth.signOut();
  redirect("/login?deleted=1");
}
