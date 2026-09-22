import "server-only";

import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import type { PlatformRole } from "@/types/database";

/**
 * These are the REAL enforcement points, not the middleware redirect (which
 * is UX-only). Every Server Component, Server Action, or Route Handler that
 * needs a signed-in user or a specific role must call one of these -- they
 * re-verify against Supabase Auth / the user_roles table (which is itself
 * RLS-protected server-side truth) on every call.
 */

export async function getCurrentUser(): Promise<User | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
}

/**
 * The real MFA step-up enforcement point (see docs/adr/0015-mfa.md).
 * Enrollment alone (supabase.auth.mfa.enroll()) means nothing if a
 * password-only session is still treated as fully authenticated -- this
 * is what actually requires the second factor before any protected
 * Server Component/Action/Route Handler proceeds, on every call, the same
 * way every other check in this file re-verifies rather than trusting a
 * prior redirect. `getAuthenticatorAssuranceLevel()` with no jwt argument
 * reads the current session and, per the Supabase SDK's own docs, "rarely
 * uses the network" -- this is not an expensive call.
 */
export async function requireUser(): Promise<User> {
  const user = await getCurrentUser();
  if (!user) {
    redirect("/login");
  }

  const supabase = await createClient();
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal && aal.nextLevel === "aal2" && aal.currentLevel !== aal.nextLevel) {
    redirect("/login/verify-mfa");
  }

  return user;
}

export async function getUserRoles(userId: string): Promise<PlatformRole[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("user_roles").select("role").eq("user_id", userId);
  if (error) {
    throw new Error(`Failed to load roles: ${error.message}`);
  }
  return (data ?? []).map((r) => r.role);
}

export async function requireRole(role: PlatformRole): Promise<User> {
  const user = await requireUser();
  const roles = await getUserRoles(user.id);
  if (!roles.includes(role) && !roles.includes("admin")) {
    redirect("/dashboard");
  }
  return user;
}

export async function requireAdmin(): Promise<User> {
  return requireRole("admin");
}
