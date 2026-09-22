"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import type { CapstoneStatus } from "@/types/database";

export interface FormState {
  error: string | null;
}

export interface ReviewFormState {
  error: string | null;
}

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const capstoneSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(8000).optional(),
  report_required: z.coerce.boolean(),
});

export async function createCapstoneAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = capstoneSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    report_required: formData.get("report_required") === "on",
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("capstones").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
    report_required: parsed.data.report_required,
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/capstones");
  return { error: null };
}

export async function updateCapstoneAction(
  capstoneId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = capstoneSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    report_required: formData.get("report_required") === "on",
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("capstones")
    .update({
      slug: parsed.data.slug,
      title: parsed.data.title,
      description: parsed.data.description || null,
      report_required: parsed.data.report_required,
    })
    .eq("id", capstoneId);
  if (error) return { error: error.message };

  revalidatePath(`/admin/capstones/${capstoneId}`);
  return { error: null };
}

export async function toggleCapstonePublishedAction(capstoneId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("capstones").update({ published }).eq("id", capstoneId);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/capstones");
  revalidatePath(`/admin/capstones/${capstoneId}`);
}

export async function setCapstoneSkillsAction(capstoneId: string, skillIds: string[]) {
  await requireAdmin();
  const supabase = await createClient();
  const { error: deleteError } = await supabase.from("capstone_skills").delete().eq("capstone_id", capstoneId);
  if (deleteError) throw new Error(deleteError.message);
  if (skillIds.length > 0) {
    const { error: insertError } = await supabase
      .from("capstone_skills")
      .insert(skillIds.map((skill_id) => ({ capstone_id: capstoneId, skill_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/capstones/${capstoneId}`);
}

const reviewSchema = z.object({
  status: z.enum(["under_review", "passed", "needs_revision"]),
  notes: z.string().trim().max(4000).optional(),
});

export async function reviewCapstoneSubmissionAction(
  submissionId: string,
  _prev: ReviewFormState,
  formData: FormData,
): Promise<ReviewFormState> {
  await requireAdmin();
  const parsed = reviewSchema.safeParse({
    status: formData.get("status"),
    notes: formData.get("notes"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("review_capstone_submission", {
    p_submission_id: submissionId,
    p_status: parsed.data.status as CapstoneStatus,
    p_notes: parsed.data.notes || null,
  });
  if (error) return { error: error.message };

  revalidatePath("/admin/capstones");
  if (data) revalidatePath(`/admin/capstones/${data.capstone_id}`);
  return { error: null };
}

export async function setCapstoneLabsAction(capstoneId: string, labIds: string[]) {
  await requireAdmin();
  const supabase = await createClient();
  const { error: deleteError } = await supabase.from("capstone_labs").delete().eq("capstone_id", capstoneId);
  if (deleteError) throw new Error(deleteError.message);
  if (labIds.length > 0) {
    const { error: insertError } = await supabase
      .from("capstone_labs")
      .insert(labIds.map((lab_id) => ({ capstone_id: capstoneId, lab_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/capstones/${capstoneId}`);
}
