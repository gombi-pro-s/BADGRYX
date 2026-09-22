"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { hashFlag } from "@/lib/security/flag-hash";
import { environmentSpecSchema } from "@/lib/terminal/spec";
import type { DifficultyLevel, LabCategory } from "@/types/database";

export interface FormState {
  error: string | null;
}

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const LAB_CATEGORIES: LabCategory[] = [
  "web",
  "api",
  "linux",
  "windows",
  "osint",
  "forensics",
  "crypto",
  "reverse_engineering",
  "cloud",
  "container",
  "misc",
];
const DIFFICULTIES: DifficultyLevel[] = ["beginner", "easy", "medium", "hard", "insane"];

const labSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(4000).optional(),
  category: z.enum(LAB_CATEGORIES as [LabCategory, ...LabCategory[]]),
  difficulty: z.enum(DIFFICULTIES as [DifficultyLevel, ...DifficultyLevel[]]),
  estimated_minutes: z.coerce.number().int().min(1).max(600),
  points: z.coerce.number().int().min(0).max(10000),
});

export async function createLabAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = labSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    category: formData.get("category"),
    difficulty: formData.get("difficulty"),
    estimated_minutes: formData.get("estimated_minutes"),
    points: formData.get("points"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("labs").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
    category: parsed.data.category,
    difficulty: parsed.data.difficulty,
    estimated_minutes: parsed.data.estimated_minutes,
    points: parsed.data.points,
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/labs");
  return { error: null };
}

export async function updateLabAction(labId: string, _prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = labSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    category: formData.get("category"),
    difficulty: formData.get("difficulty"),
    estimated_minutes: formData.get("estimated_minutes"),
    points: formData.get("points"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("labs")
    .update({
      slug: parsed.data.slug,
      title: parsed.data.title,
      description: parsed.data.description || null,
      category: parsed.data.category,
      difficulty: parsed.data.difficulty,
      estimated_minutes: parsed.data.estimated_minutes,
      points: parsed.data.points,
    })
    .eq("id", labId);
  if (error) return { error: error.message };

  revalidatePath(`/admin/labs/${labId}`);
  return { error: null };
}

export async function toggleLabPublishedAction(labId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("labs").update({ published }).eq("id", labId);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/labs");
  revalidatePath(`/admin/labs/${labId}`);
}

export async function setLabSkillsAction(labId: string, skillIds: string[]) {
  await requireAdmin();
  const supabase = await createClient();
  const { error: deleteError } = await supabase.from("lab_skills").delete().eq("lab_id", labId);
  if (deleteError) throw new Error(deleteError.message);
  if (skillIds.length > 0) {
    const { error: insertError } = await supabase
      .from("lab_skills")
      .insert(skillIds.map((skill_id) => ({ lab_id: labId, skill_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/labs/${labId}`);
}

// ---- Hints --------------------------------------------------------------------

const hintSchema = z.object({
  level: z.coerce.number().int().min(1).max(5),
  content: z.string().trim().min(1).max(2000),
  point_cost: z.coerce.number().int().min(0).max(1000),
});

export async function createHintAction(labId: string, _prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = hintSchema.safeParse({
    level: formData.get("level"),
    content: formData.get("content"),
    point_cost: formData.get("point_cost"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("lab_hints").insert({
    lab_id: labId,
    level: parsed.data.level,
    content: parsed.data.content,
    point_cost: parsed.data.point_cost,
  });
  if (error) return { error: error.code === "23505" ? "A hint already exists at that level." : error.message };

  revalidatePath(`/admin/labs/${labId}`);
  return { error: null };
}

export async function deleteHintAction(labId: string, hintId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("lab_hints").delete().eq("id", hintId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/labs/${labId}`);
}

// ---- Flags ----------------------------------------------------------------
//
// The plaintext flag is hashed here, server-side, and only the hash ever
// reaches the database. It is never logged, never returned to the client,
// and discarded the moment this function returns.

const flagSchema = z.object({
  label: z.string().trim().min(1).max(100),
  plaintext: z.string().trim().min(4, "Flag must be at least 4 characters.").max(500),
  variant_seed: z.coerce.number().int().min(0).max(9999),
});

export async function createFlagAction(labId: string, _prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = flagSchema.safeParse({
    label: formData.get("label"),
    plaintext: formData.get("plaintext"),
    variant_seed: formData.get("variant_seed"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("lab_flags").insert({
    lab_id: labId,
    label: parsed.data.label,
    flag_hash: hashFlag(parsed.data.plaintext),
    variant_seed: parsed.data.variant_seed,
  });
  if (error) {
    return {
      error: error.code === "23505" ? "A flag with that label/variant already exists." : error.message,
    };
  }

  revalidatePath(`/admin/labs/${labId}`);
  return { error: null };
}

export async function deleteFlagAction(labId: string, flagId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("lab_flags").delete().eq("id", flagId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/labs/${labId}`);
}

// ---- Terminal environment ---------------------------------------------------
//
// The spec is validated with the exact same zod schema
// (lib/terminal/spec.ts's environmentSpecSchema) the terminal execution
// engine parses it with, so a spec that saves here is guaranteed to be one
// lib/terminal/execute.ts can actually run -- an admin can't save something
// invalid and only discover it's broken when a learner hits it.

const environmentFormSchema = z.object({
  variant_seed: z.coerce.number().int().min(0).max(9999),
  spec_json: z.string().trim().min(1, "Spec JSON is required."),
});

export async function saveEnvironmentAction(labId: string, _prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = environmentFormSchema.safeParse({
    variant_seed: formData.get("variant_seed"),
    spec_json: formData.get("spec_json"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  let rawSpec: unknown;
  try {
    rawSpec = JSON.parse(parsed.data.spec_json);
  } catch {
    return { error: "Spec is not valid JSON." };
  }

  const specParsed = environmentSpecSchema.safeParse(rawSpec);
  if (!specParsed.success) {
    return { error: `Spec failed validation: ${specParsed.error.issues[0]?.message} (at ${specParsed.error.issues[0]?.path.join(".")})` };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("lab_environments").upsert(
    {
      lab_id: labId,
      variant_seed: parsed.data.variant_seed,
      // EnvironmentSpec has known fields, not an index signature -- jsonb
      // storage doesn't care about that distinction (see the same cast in
      // lib/terminal/execute.ts).
      spec: specParsed.data as unknown as Record<string, unknown>,
    },
    { onConflict: "lab_id,variant_seed" },
  );
  if (error) return { error: error.message };

  revalidatePath(`/admin/labs/${labId}`);
  return { error: null };
}

export async function deleteEnvironmentAction(labId: string, environmentId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("lab_environments").delete().eq("id", environmentId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/labs/${labId}`);
}
