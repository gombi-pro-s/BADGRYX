import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireOrgMembership } from "@/lib/auth/org";
import { createClient } from "@/lib/supabase/server";
import { InviteForm } from "./invite-form";
import { RevokeInviteButton } from "./revoke-invite-button";
import { revokeInvitationAction } from "../actions";
import type { OrgRole } from "@/types/database";

export const metadata: Metadata = { title: "Organization" };

const ADMIN_ROLES: OrgRole[] = ["team_owner", "org_admin"];
const INSTRUCTOR_ROLES: OrgRole[] = ["instructor", "team_owner", "org_admin"];

export default async function OrganizationDetailPage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  const { role } = await requireOrgMembership(orgId);
  const supabase = await createClient();

  const { data: organization } = await supabase.from("organizations").select("*").eq("id", orgId).maybeSingle();
  if (!organization) notFound();

  const { data: members } = await supabase
    .from("organization_members")
    .select("id, user_id, role, joined_at")
    .eq("organization_id", orgId)
    .order("joined_at");

  const memberIds = (members ?? []).map((m) => m.user_id);
  const { data: profiles } =
    memberIds.length > 0
      ? await supabase.from("profiles").select("id, display_name, username").in("id", memberIds)
      : { data: [] };
  const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));

  const isAdmin = ADMIN_ROLES.includes(role);
  const isInstructor = INSTRUCTOR_ROLES.includes(role);

  // Only an org admin's own RLS session can actually see pending invitations
  // (org_invitations_select_org_admin) -- this query returns empty for a
  // plain member, which is the correct behavior, not a bug to work around.
  const { data: invitations } = isAdmin
    ? await supabase
        .from("organization_invitations")
        .select("id, email, role, expires_at, accepted_at, revoked_at, created_at")
        .eq("organization_id", orgId)
        .order("created_at", { ascending: false })
    : { data: null };

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <div className="mb-1 flex items-center justify-between">
        <h1 className="text-2xl font-semibold text-foreground">{organization.name}</h1>
        <span className="rounded-full bg-accent-muted px-2.5 py-0.5 text-xs font-medium text-accent">
          {role.replace("_", " ")}
        </span>
      </div>
      <p className="mb-8 text-sm text-foreground-subtle">{organization.slug}</p>

      {isInstructor && (
        <Link
          href={`/orgs/${orgId}/dashboard`}
          className="mb-8 block rounded-lg border border-accent/30 bg-accent-muted px-4 py-3 text-sm font-medium text-accent hover:opacity-90"
        >
          Open instructor dashboard &rarr;
        </Link>
      )}

      <h2 className="mb-3 text-sm font-semibold text-foreground">Members ({members?.length ?? 0})</h2>
      <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
        {(members ?? []).map((m) => {
          const profile = profileById.get(m.user_id);
          return (
            <li key={m.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <span className="text-sm text-foreground">{profile?.display_name ?? profile?.username ?? m.user_id}</span>
              <span className="shrink-0 rounded-full bg-background-subtle px-2.5 py-0.5 text-xs font-medium text-foreground-muted">
                {m.role.replace("_", " ")}
              </span>
            </li>
          );
        })}
      </ul>

      {isAdmin && (
        <div className="space-y-6">
          <InviteForm organizationId={orgId} />

          {invitations && invitations.length > 0 && (
            <div className="rounded-lg border border-border bg-surface p-5">
              <h2 className="mb-3 text-sm font-semibold text-foreground">Invitations</h2>
              <ul className="divide-y divide-border">
                {invitations.map((inv) => {
                  const status = inv.revoked_at
                    ? "Revoked"
                    : inv.accepted_at
                      ? "Accepted"
                      : new Date(inv.expires_at) < new Date()
                        ? "Expired"
                        : "Pending";
                  return (
                    <li key={inv.id} className="flex items-center justify-between gap-4 py-2.5">
                      <div>
                        <p className="text-sm text-foreground">{inv.email}</p>
                        <p className="text-xs text-foreground-subtle">
                          {inv.role.replace("_", " ")} &middot; {status}
                        </p>
                      </div>
                      {status === "Pending" && (
                        <RevokeInviteButton onRevoke={revokeInvitationAction.bind(null, orgId, inv.id)} />
                      )}
                    </li>
                  );
                })}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
