"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { logPublishToggle } from "@/lib/audit";

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

/**
 * Upserts or removes the announcement's Spanish translation depending on
 * whether both fields are filled in -- an announcement's translation is
 * optional, so a blank pair means "no translation", not "empty strings".
 * Only 'es' exists as an optional field today since SUPPORTED_LOCALES is
 * ['en', 'es'] and 'en' is the base row itself; adding a third locale
 * means a new field pair here too. See ADR 0038.
 */
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

/** Platform-wide announcements only (organization_id stays NULL) -- an
 * org's own instructors author their org-scoped announcements from
 * /orgs/[orgId]/announcements instead, under the same RLS policy. */
export async function createAnnouncementAction(_prev: FormState, formData: FormData): Promise<FormState> {
  const admin = await requireAdmin();
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
      title: parsed.data.title,
      body_markdown: parsed.data.body_markdown,
      expires_at: parsed.data.expires_at,
      created_by: admin.id,
    })
    .select("id")
    .single();
  if (error || !created) return { error: error?.message ?? "Could not create the announcement." };

  try {
    await upsertSpanishTranslation(supabase, created.id, parsed.data.title_es, parsed.data.body_markdown_es);
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Could not save the Spanish translation." };
  }

  revalidatePath("/admin/announcements");
  return { error: null };
}

export async function updateAnnouncementAction(
  announcementId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
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
    .eq("id", announcementId);
  if (error) return { error: error.message };

  try {
    await upsertSpanishTranslation(supabase, announcementId, parsed.data.title_es, parsed.data.body_markdown_es);
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Could not save the Spanish translation." };
  }

  revalidatePath("/admin/announcements");
  revalidatePath(`/admin/announcements/${announcementId}`);
  return { error: null };
}

export async function toggleAnnouncementPublishedAction(announcementId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase
    .from("announcements")
    .update({ published, published_at: published ? new Date().toISOString() : null })
    .eq("id", announcementId);
  if (error) throw new Error(error.message);
  await logPublishToggle(supabase, "announcement", announcementId, published);
  revalidatePath("/admin/announcements");
  revalidatePath(`/admin/announcements/${announcementId}`);
}

/**
 * Unlike every other content type in this CMS, announcements really do get
 * deleted outright rather than just unpublished -- nothing else in the
 * schema references an announcement's id (no learner progress, no
 * evidence, nothing graded), so there's no "orphaned reference" risk a
 * delete could create. A stale notice is meant to go away, not linger as
 * an unpublished draft forever.
 */
export async function deleteAnnouncementAction(announcementId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("announcements").delete().eq("id", announcementId);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/announcements");
  redirect("/admin/announcements");
}
