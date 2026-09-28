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
  title_es: z.string().trim().max(200).optional(),
  body_markdown_es: z.string().trim().optional(),
});

/** Mirrors admin/announcements/actions.ts's upsertSpanishTranslation exactly
 * -- see that file's comment for why only 'es' exists as a field pair. */
async function upsertSpanishTranslation(
  supabase: Awaited<ReturnType<typeof createClient>>,
  announcementId: string,
  titleEs: string | undefined,
  bodyEs: string | undefined,
) {
  if (titleEs && bodyEs) {
    const { error } = await supabase
      .from("announcement_translations")
      .upsert(
        { announcement_id: announcementId, locale: "es", title: titleEs, body_markdown: bodyEs },
        { onConflict: "announcement_id,locale" },
      );
    if (error) throw new Error(error.message);
  } else {
    const { error } = await supabase
      .from("announcement_translations")
      .delete()
      .eq("announcement_id", announcementId)
      .eq("locale", "es");
    if (error) throw new Error(error.message);
  }
}

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
    title_es: formData.get("title_es"),
    body_markdown_es: formData.get("body_markdown_es"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { data: created, error } = await supabase
    .from("announcements")
    .insert({
      organization_id: organizationId,
      title: parsed.data.title,
      body_markdown: parsed.data.body_markdown,
      expires_at: parsed.data.expires_at,
      created_by: user.id,
    })
    .select("id")
    .single();
  if (error || !created) return { error: error?.message ?? "Could not create the announcement." };

  try {
    await upsertSpanishTranslation(supabase, created.id, parsed.data.title_es, parsed.data.body_markdown_es);
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Could not save the Spanish translation." };
  }

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
    title_es: formData.get("title_es"),
    body_markdown_es: formData.get("body_markdown_es"),
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

  try {
    await upsertSpanishTranslation(supabase, announcementId, parsed.data.title_es, parsed.data.body_markdown_es);
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Could not save the Spanish translation." };
  }

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
