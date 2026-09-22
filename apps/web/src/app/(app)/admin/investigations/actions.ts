"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { hashInvestigationAnswer } from "@/lib/security/answer-hash";
import type { DifficultyLevel, InvestigationArtifactType, LabCategory } from "@/types/database";

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

const investigationSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  briefing: z.string().trim().max(8000).optional(),
  category: z.enum(LAB_CATEGORIES as [LabCategory, ...LabCategory[]]),
  difficulty: z.enum(DIFFICULTIES as [DifficultyLevel, ...DifficultyLevel[]]),
  estimated_minutes: z.coerce.number().int().min(1).max(600),
  points: z.coerce.number().int().min(0).max(10000),
  passing_score: z.coerce.number().int().min(0).max(100),
});

export async function createInvestigationAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = investigationSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    briefing: formData.get("briefing"),
    category: formData.get("category"),
    difficulty: formData.get("difficulty"),
    estimated_minutes: formData.get("estimated_minutes"),
    points: formData.get("points"),
    passing_score: formData.get("passing_score"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("investigations").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    briefing: parsed.data.briefing || null,
    category: parsed.data.category,
    difficulty: parsed.data.difficulty,
    estimated_minutes: parsed.data.estimated_minutes,
    points: parsed.data.points,
    passing_score: parsed.data.passing_score,
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/investigations");
  return { error: null };
}

export async function updateInvestigationAction(
  investigationId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = investigationSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    briefing: formData.get("briefing"),
    category: formData.get("category"),
    difficulty: formData.get("difficulty"),
    estimated_minutes: formData.get("estimated_minutes"),
    points: formData.get("points"),
    passing_score: formData.get("passing_score"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("investigations")
    .update({
      slug: parsed.data.slug,
      title: parsed.data.title,
      briefing: parsed.data.briefing || null,
      category: parsed.data.category,
      difficulty: parsed.data.difficulty,
      estimated_minutes: parsed.data.estimated_minutes,
      points: parsed.data.points,
      passing_score: parsed.data.passing_score,
    })
    .eq("id", investigationId);
  if (error) return { error: error.message };

  revalidatePath(`/admin/investigations/${investigationId}`);
  return { error: null };
}

export async function toggleInvestigationPublishedAction(investigationId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("investigations").update({ published }).eq("id", investigationId);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/investigations");
  revalidatePath(`/admin/investigations/${investigationId}`);
}

export async function setInvestigationSkillsAction(investigationId: string, skillIds: string[]) {
  await requireAdmin();
  const supabase = await createClient();
  const { error: deleteError } = await supabase.from("investigation_skills").delete().eq("investigation_id", investigationId);
  if (deleteError) throw new Error(deleteError.message);
  if (skillIds.length > 0) {
    const { error: insertError } = await supabase
      .from("investigation_skills")
      .insert(skillIds.map((skill_id) => ({ investigation_id: investigationId, skill_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/investigations/${investigationId}`);
}

// ---- Artifacts --------------------------------------------------------------

const ARTIFACT_TYPES: InvestigationArtifactType[] = [
  "whois_record",
  "email_headers",
  "social_media_profile",
  "file_metadata",
  "log_excerpt",
  "network_capture_summary",
  "document_excerpt",
  "chat_transcript",
];

const artifactSchema = z.object({
  artifact_type: z.enum(ARTIFACT_TYPES as [InvestigationArtifactType, ...InvestigationArtifactType[]]),
  title: z.string().trim().min(1).max(200),
  content: z.string().trim().min(1).max(20000),
});

export async function createArtifactAction(
  investigationId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireAdmin();
  const parsed = artifactSchema.safeParse({
    artifact_type: formData.get("artifact_type"),
    title: formData.get("title"),
    content: formData.get("content"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { count } = await supabase
    .from("investigation_artifacts")
    .select("id", { count: "exact", head: true })
    .eq("investigation_id", investigationId);

  const { error } = await supabase.from("investigation_artifacts").insert({
    investigation_id: investigationId,
    artifact_type: parsed.data.artifact_type,
    title: parsed.data.title,
    content: parsed.data.content,
    order_index: count ?? 0,
  });
  if (error) return { error: error.message };

  revalidatePath(`/admin/investigations/${investigationId}`);
  return { error: null };
}

export async function deleteArtifactAction(investigationId: string, artifactId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("investigation_artifacts").delete().eq("id", artifactId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/investigations/${investigationId}`);
}

// ---- Questions ----------------------------------------------------------------
//
// exact_text answers are hashed here, server-side, the same discipline as
// lab/CTF flags -- the plaintext never reaches the database or the client
// after this function returns.

export interface ChoiceInput {
  text: string;
  isCorrect: boolean;
}

export async function createMultipleChoiceQuestionAction(
  investigationId: string,
  questionText: string,
  points: number,
  choices: ChoiceInput[],
) {
  await requireAdmin();

  const trimmedText = questionText.trim();
  if (!trimmedText) throw new Error("Question text is required.");
  const validChoices = choices.map((c) => ({ ...c, text: c.text.trim() })).filter((c) => c.text.length > 0);
  if (validChoices.length < 2) throw new Error("At least two choices are required.");
  if (!validChoices.some((c) => c.isCorrect)) throw new Error("At least one choice must be marked correct.");

  const supabase = await createClient();
  const { data: question, error: questionError } = await supabase
    .from("investigation_questions")
    .insert({
      investigation_id: investigationId,
      question_text: trimmedText,
      question_type: "multiple_choice",
      points,
    })
    .select("id")
    .single();
  if (questionError || !question) throw new Error(questionError?.message ?? "Failed to create question.");

  const { error: choicesError } = await supabase.from("investigation_choices").insert(
    validChoices.map((c, i) => ({
      question_id: question.id,
      choice_text: c.text,
      is_correct: c.isCorrect,
      order_index: i,
    })),
  );
  if (choicesError) throw new Error(choicesError.message);

  revalidatePath(`/admin/investigations/${investigationId}`);
}

export async function createExactTextQuestionAction(
  investigationId: string,
  questionText: string,
  points: number,
  plaintextAnswer: string,
) {
  await requireAdmin();

  const trimmedText = questionText.trim();
  if (!trimmedText) throw new Error("Question text is required.");
  if (plaintextAnswer.trim().length < 1) throw new Error("An answer is required.");

  const supabase = await createClient();
  const { error } = await supabase.from("investigation_questions").insert({
    investigation_id: investigationId,
    question_text: trimmedText,
    question_type: "exact_text",
    points,
    answer_hash: hashInvestigationAnswer(plaintextAnswer),
  });
  if (error) throw new Error(error.message);

  revalidatePath(`/admin/investigations/${investigationId}`);
}

export async function deleteQuestionAction(investigationId: string, questionId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("investigation_questions").delete().eq("id", questionId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/investigations/${investigationId}`);
}
