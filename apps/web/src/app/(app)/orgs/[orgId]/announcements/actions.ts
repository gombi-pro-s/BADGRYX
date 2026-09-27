"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireOrgInstructor } from "@/lib/auth/org";
import { createClient } from "@/lib/supabase/server";

export interface FormState {
  error: string | null;
}

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const announcementSchema = z.object({
  title: z.string().trim().min(1).max(200),
  body_markdown: z.string().trim().min(1, "Announcement body is required."),
  expires_at: z
    .string()
    .trim()
    .optional()
    .transform((v) => (v ? new Date(v).toISOString() : null)),
});

export async function createOrgAnnouncementAction(
  organizationId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const { user } = await requireOrgInstructor(organizationId);
  const parsed = announcementSchema.safeParse({
    title: formData.get("title"),
    body_markdown: formData.get("body_markdown"),
    expires_at: formData.get("expires_at"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("announcements").insert({
    organization_id: organizationId,
    title: parsed.data.title,
    body_markdown: parsed.data.body_markdown,
    expires_at: parsed.data.expires_at,
    created_by: user.id,
  });
  if (error) return { error: error.message };

  revalidatePath(`/orgs/${organizationId}/announcements`);
  return { error: null };
}

export async function updateOrgAnnouncementAction(
  organizationId: string,
  announcementId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireOrgInstructor(organizationId);
  const parsed = announcementSchema.safeParse({
    title: formData.get("title"),
    body_markdown: formData.get("body_markdown"),
    expires_at: formData.get("expires_at"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("announcements")
    .update({
      title: parsed.data.title,
      body_markdown: parsed.data.body_markdown,
      expires_at: parsed.data.expires_at,
    })
    .eq("id", announcementId)
    .eq("organization_id", organizationId);
  if (error) return { error: error.message };

  revalidatePath(`/orgs/${organizationId}/announcements`);
  revalidatePath(`/orgs/${organizationId}/announcements/${announcementId}`);
  return { error: null };
}

export async function toggleOrgAnnouncementPublishedAction(
  organizationId: string,
  announcementId: string,
  published: boolean,
) {
  await requireOrgInstructor(organizationId);
  const supabase = await createClient();
  const { error } = await supabase
    .from("announcements")
    .update({ published, published_at: published ? new Date().toISOString() : null })
    .eq("id", announcementId)
    .eq("organization_id", organizationId);
  if (error) throw new Error(error.message);
  revalidatePath(`/orgs/${organizationId}/announcements`);
  revalidatePath(`/orgs/${organizationId}/announcements/${announcementId}`);
}

export async function deleteOrgAnnouncementAction(organizationId: string, announcementId: string) {
  await requireOrgInstructor(organizationId);
  const supabase = await createClient();
  const { error } = await supabase
    .from("announcements")
    .delete()
    .eq("id", announcementId)
    .eq("organization_id", organizationId);
  if (error) throw new Error(error.message);
  revalidatePath(`/orgs/${organizationId}/announcements`);
  redirect(`/orgs/${organizationId}/announcements`);
}
