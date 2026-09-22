"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { requireOrgAdmin } from "@/lib/auth/org";
import { createClient } from "@/lib/supabase/server";
import { logAuditEvent } from "@/lib/audit";
import type { OrgRole } from "@/types/database";

export interface FormState {
  error: string | null;
}

export interface InviteFormState {
  error: string | null;
  // The raw invitation token/link, shown exactly once -- there is no email
  // service in this app (see docs/adr/0010-org-invitations-manual-link.md),
  // so the admin must copy it and send it themselves.
  inviteLink: string | null;
}

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const organizationSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only (3-64 chars)."),
  name: z.string().trim().min(1).max(200),
});

export async function createOrganizationAction(_prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requireUser();
  const parsed = organizationSchema.safeParse({
    slug: formData.get("slug"),
    name: formData.get("name"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organizations")
    .insert({ slug: parsed.data.slug, name: parsed.data.name, created_by: user.id })
    .select("id")
    .single();
  if (error || !data) {
    return { error: error?.code === "23505" ? "That slug is already in use." : (error?.message ?? "Failed to create organization.") };
  }

  await logAuditEvent(supabase, "organization.created", "organization", data.id, data.id, { slug: parsed.data.slug });

  redirect(`/orgs/${data.id}`);
}

const INVITE_ROLES: OrgRole[] = ["member", "instructor", "team_owner", "org_admin"];

const inviteSchema = z.object({
  email: z.string().trim().email("Enter a valid email address."),
  role: z.enum(INVITE_ROLES as [OrgRole, ...OrgRole[]]),
});

export async function createInvitationAction(
  organizationId: string,
  _prev: InviteFormState,
  formData: FormData,
): Promise<InviteFormState> {
  await requireOrgAdmin(organizationId);
  const parsed = inviteSchema.safeParse({
    email: formData.get("email"),
    role: formData.get("role"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input."), inviteLink: null };

  const supabase = await createClient();
  const { data: token, error } = await supabase.rpc("create_organization_invitation", {
    p_organization_id: organizationId,
    p_email: parsed.data.email,
    p_role: parsed.data.role,
  });
  if (error || !token) return { error: error?.message ?? "Failed to create invitation.", inviteLink: null };

  revalidatePath(`/orgs/${organizationId}`);
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "";
  return { error: null, inviteLink: `${siteUrl}/invite/${token}` };
}

export async function revokeInvitationAction(organizationId: string, invitationId: string) {
  await requireOrgAdmin(organizationId);
  const supabase = await createClient();
  const { error } = await supabase
    .from("organization_invitations")
    .update({ revoked_at: new Date().toISOString() })
    .eq("id", invitationId);
  if (error) throw new Error(error.message);
  await logAuditEvent(supabase, "org.invitation.revoked", "organization_invitation", invitationId, organizationId);
  revalidatePath(`/orgs/${organizationId}`);
}

export interface AcceptInviteState {
  error: string | null;
}

export async function acceptInvitationAction(token: string): Promise<AcceptInviteState> {
  await requireUser();
  const supabase = await createClient();
  const { data: member, error } = await supabase.rpc("accept_organization_invitation", { p_token: token });
  if (error || !member) return { error: error?.message ?? "Failed to accept invitation." };

  redirect(`/orgs/${member.organization_id}`);
}
