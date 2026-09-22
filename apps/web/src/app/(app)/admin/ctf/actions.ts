"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { hashFlag } from "@/lib/security/flag-hash";
import { logPublishToggle } from "@/lib/audit";
import type { CtfChallengeRow, DifficultyLevel, LabCategory } from "@/types/database";

export interface FormState {
  error: string | null;
}

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const CATEGORIES: LabCategory[] = [
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

const createSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(4000).optional(),
  category: z.enum(CATEGORIES as [LabCategory, ...LabCategory[]]),
  difficulty: z.enum(DIFFICULTIES as [DifficultyLevel, ...DifficultyLevel[]]),
  points: z.coerce.number().int().min(0).max(10000),
  plaintext: z.string().trim().min(4, "Flag must be at least 4 characters.").max(500),
});

export async function createChallengeAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = createSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    category: formData.get("category"),
    difficulty: formData.get("difficulty"),
    points: formData.get("points"),
    plaintext: formData.get("plaintext"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("ctf_challenges").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
    category: parsed.data.category,
    difficulty: parsed.data.difficulty,
    points: parsed.data.points,
    flag_hash: hashFlag(parsed.data.plaintext),
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/ctf");
  return { error: null };
}

const updateSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(4000).optional(),
  category: z.enum(CATEGORIES as [LabCategory, ...LabCategory[]]),
  difficulty: z.enum(DIFFICULTIES as [DifficultyLevel, ...DifficultyLevel[]]),
  points: z.coerce.number().int().min(0).max(10000),
  plaintext: z.string().trim().max(500).optional(), // blank = keep existing flag
});

export async function updateChallengeAction(
  challengeId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = updateSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    category: formData.get("category"),
    difficulty: formData.get("difficulty"),
    points: formData.get("points"),
    plaintext: formData.get("plaintext"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };
  if (parsed.data.plaintext && parsed.data.plaintext.length < 4) {
    return { error: "New flag must be at least 4 characters." };
  }

  const supabase = await createClient();
  const update: Partial<CtfChallengeRow> = {
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
    category: parsed.data.category,
    difficulty: parsed.data.difficulty,
    points: parsed.data.points,
  };
  if (parsed.data.plaintext) {
    update.flag_hash = hashFlag(parsed.data.plaintext);
  }

  const { error } = await supabase.from("ctf_challenges").update(update).eq("id", challengeId);
  if (error) return { error: error.message };

  revalidatePath(`/admin/ctf/${challengeId}`);
  return { error: null };
}

export async function toggleChallengePublishedAction(challengeId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("ctf_challenges").update({ published }).eq("id", challengeId);
  if (error) throw new Error(error.message);
  await logPublishToggle(supabase, "ctf_challenge", challengeId, published);
  revalidatePath("/admin/ctf");
  revalidatePath(`/admin/ctf/${challengeId}`);
}

export async function setChallengeSkillsAction(challengeId: string, skillIds: string[]) {
  await requireAdmin();
  const supabase = await createClient();
  const { error: deleteError } = await supabase
    .from("ctf_challenge_skills")
    .delete()
    .eq("challenge_id", challengeId);
  if (deleteError) throw new Error(deleteError.message);
  if (skillIds.length > 0) {
    const { error: insertError } = await supabase
      .from("ctf_challenge_skills")
      .insert(skillIds.map((skill_id) => ({ challenge_id: challengeId, skill_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/ctf/${challengeId}`);
}
