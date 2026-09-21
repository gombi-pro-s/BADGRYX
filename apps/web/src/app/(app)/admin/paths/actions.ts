"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export interface FormState {
  error: string | null;
}

const slugSchema = z
  .string()
  .trim()
  .regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, and hyphens only (3-64 chars).");

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

// ---- Learning paths ---------------------------------------------------------

const pathSchema = z.object({
  slug: slugSchema,
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(2000).optional(),
});

export async function createPathAction(_prev: FormState, formData: FormData): Promise<FormState> {
  // requireAdmin() is UX-fast-fail here; the real enforcement is the
  // learning_paths_staff_write RLS policy on the insert itself.
  const admin = await requireAdmin();
  const parsed = pathSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("learning_paths").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
    created_by: admin.id,
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/paths");
  return { error: null };
}

export async function updatePathAction(
  pathId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = pathSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("learning_paths")
    .update({
      slug: parsed.data.slug,
      title: parsed.data.title,
      description: parsed.data.description || null,
    })
    .eq("id", pathId);
  if (error) return { error: error.message };

  revalidatePath("/admin/paths");
  revalidatePath(`/admin/paths/${pathId}`);
  return { error: null };
}

export async function togglePathPublishedAction(pathId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("learning_paths").update({ published }).eq("id", pathId);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/paths");
  revalidatePath(`/admin/paths/${pathId}`);
}

// ---- Modules ----------------------------------------------------------------

const moduleSchema = z.object({
  slug: slugSchema,
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(2000).optional(),
});

export async function createModuleAction(
  pathId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = moduleSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("modules").insert({
    path_id: pathId,
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
  });
  if (error) return { error: error.code === "23505" ? "That slug already exists in this path." : error.message };

  revalidatePath(`/admin/paths/${pathId}`);
  return { error: null };
}

export async function toggleModulePublishedAction(pathId: string, moduleId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("modules").update({ published }).eq("id", moduleId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/paths/${pathId}`);
  revalidatePath(`/admin/paths/${pathId}/${moduleId}`);
}

// ---- Lessons ------------------------------------------------------------------

const lessonSchema = z.object({
  slug: slugSchema,
  title: z.string().trim().min(1).max(200),
  summary: z.string().trim().max(500).optional(),
  content_markdown: z.string().trim().min(1, "Lesson content is required."),
  estimated_minutes: z.coerce.number().int().min(1).max(600),
});

export async function createLessonAction(
  pathId: string,
  moduleId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = lessonSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    summary: formData.get("summary"),
    content_markdown: formData.get("content_markdown"),
    estimated_minutes: formData.get("estimated_minutes"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("lessons").insert({
    module_id: moduleId,
    slug: parsed.data.slug,
    title: parsed.data.title,
    summary: parsed.data.summary || null,
    content_markdown: parsed.data.content_markdown,
    estimated_minutes: parsed.data.estimated_minutes,
  });
  if (error) return { error: error.code === "23505" ? "That slug already exists in this module." : error.message };

  revalidatePath(`/admin/paths/${pathId}/${moduleId}`);
  return { error: null };
}

export async function updateLessonAction(
  pathId: string,
  moduleId: string,
  lessonId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = lessonSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    summary: formData.get("summary"),
    content_markdown: formData.get("content_markdown"),
    estimated_minutes: formData.get("estimated_minutes"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("lessons")
    .update({
      slug: parsed.data.slug,
      title: parsed.data.title,
      summary: parsed.data.summary || null,
      content_markdown: parsed.data.content_markdown,
      estimated_minutes: parsed.data.estimated_minutes,
    })
    .eq("id", lessonId);
  if (error) return { error: error.message };

  revalidatePath(`/admin/paths/${pathId}/${moduleId}/${lessonId}`);
  return { error: null };
}

export async function toggleLessonPublishedAction(
  pathId: string,
  moduleId: string,
  lessonId: string,
  published: boolean,
) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("lessons").update({ published }).eq("id", lessonId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/paths/${pathId}/${moduleId}`);
  revalidatePath(`/admin/paths/${pathId}/${moduleId}/${lessonId}`);
}

export async function setLessonSkillsAction(
  pathId: string,
  moduleId: string,
  lessonId: string,
  skillIds: string[],
) {
  await requireAdmin();
  const supabase = await createClient();
  // Replace the full set: simplest correct semantics for a multi-select
  // "which skills does this lesson teach" control.
  const { error: deleteError } = await supabase.from("lesson_skills").delete().eq("lesson_id", lessonId);
  if (deleteError) throw new Error(deleteError.message);
  if (skillIds.length > 0) {
    const { error: insertError } = await supabase
      .from("lesson_skills")
      .insert(skillIds.map((skill_id) => ({ lesson_id: lessonId, skill_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/paths/${pathId}/${moduleId}/${lessonId}`);
}
