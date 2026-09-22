import "server-only";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireUser } from "@/lib/auth/session";
import type { OrganizationRow, OrgRole } from "@/types/database";

/**
 * Org-scoped role helpers, mirroring the platform-role helpers in
 * ./session.ts. Every one of these re-reads organization_members through the
 * caller's own RLS-scoped session -- there is no separate trust boundary
 * here, RLS is still the real enforcement (is_org_admin()/is_org_member() in
 * SQL do the same checks independently for any direct table/RPC access).
 */

const INSTRUCTOR_ROLES: OrgRole[] = ["instructor", "team_owner", "org_admin"];
const ADMIN_ROLES: OrgRole[] = ["team_owner", "org_admin"];

export async function getUserOrgRole(organizationId: string, userId: string): Promise<OrgRole | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organization_members")
    .select("role")
    .eq("organization_id", organizationId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to load org role: ${error.message}`);
  }
  return data?.role ?? null;
}

export interface OrgMembership {
  role: OrgRole;
  organization: OrganizationRow;
}

/** Every organization the given user belongs to, with their role in each. */
export async function getUserOrganizations(userId: string): Promise<OrgMembership[]> {
  const supabase = await createClient();
  const { data: memberships, error } = await supabase
    .from("organization_members")
    .select("organization_id, role")
    .eq("user_id", userId);
  if (error) {
    throw new Error(`Failed to load organization memberships: ${error.message}`);
  }
  if (!memberships || memberships.length === 0) return [];

  const { data: organizations, error: orgError } = await supabase
    .from("organizations")
    .select("*")
    .in(
      "id",
      memberships.map((m) => m.organization_id),
    );
  if (orgError) {
    throw new Error(`Failed to load organizations: ${orgError.message}`);
  }

  const byId = new Map((organizations ?? []).map((o) => [o.id, o]));
  return memberships
    .map((m) => {
      const organization = byId.get(m.organization_id);
      return organization ? { role: m.role, organization } : null;
    })
    .filter((m): m is OrgMembership => m !== null);
}

/** Requires the current user to belong to the org at all; redirects otherwise. */
export async function requireOrgMembership(organizationId: string) {
  const user = await requireUser();
  const role = await getUserOrgRole(organizationId, user.id);
  if (!role) {
    redirect("/dashboard");
  }
  return { user, role };
}

/** Requires instructor/team_owner/org_admin -- can view member progress. */
export async function requireOrgInstructor(organizationId: string) {
  const { user, role } = await requireOrgMembership(organizationId);
  if (!INSTRUCTOR_ROLES.includes(role)) {
    redirect(`/orgs/${organizationId}`);
  }
  return { user, role };
}

/** Requires team_owner/org_admin -- can manage membership and invitations. */
export async function requireOrgAdmin(organizationId: string) {
  const { user, role } = await requireOrgMembership(organizationId);
  if (!ADMIN_ROLES.includes(role)) {
    redirect(`/orgs/${organizationId}`);
  }
  return { user, role };
}
