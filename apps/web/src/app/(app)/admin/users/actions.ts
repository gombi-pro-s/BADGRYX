"use server";

import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import type { AdminUserSearchResult, PlatformRole } from "@/types/database";

export interface SearchState {
  results: AdminUserSearchResult[];
  error: string | null;
}

export async function searchUsersAction(_prev: SearchState, formData: FormData): Promise<SearchState> {
  await requireAdmin();
  const query = String(formData.get("query") ?? "");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_search_users", { p_query: query });
  if (error) return { results: [], error: error.message };

  return { results: data ?? [], error: null };
}

export async function grantRoleAction(userId: string, role: PlatformRole) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.rpc("grant_platform_role", { p_user_id: userId, p_role: role });
  if (error) throw new Error(error.message);
  revalidatePath("/admin/users");
}

export async function revokeRoleAction(userId: string, role: PlatformRole) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.rpc("revoke_platform_role", { p_user_id: userId, p_role: role });
  if (error) throw new Error(error.message);
  revalidatePath("/admin/users");
}
