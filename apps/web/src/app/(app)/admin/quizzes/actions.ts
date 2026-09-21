"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import type { HintPolicy, QuestionType } from "@/types/database";

export interface FormState {
  error: string | null;
}

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const HINT_POLICIES: HintPolicy[] = ["none", "limited", "full"];

const quizSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  passing_score: z.coerce.number().min(0).max(100),
  is_exam: z.coerce.boolean(),
  time_limit_minutes: z.coerce.number().int().min(1).max(600).optional(),
  hint_policy: z.enum(HINT_POLICIES as [HintPolicy, ...HintPolicy[]]),
});

export async function createQuizAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = quizSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    passing_score: formData.get("passing_score"),
    is_exam: formData.get("is_exam") === "on",
    time_limit_minutes: formData.get("time_limit_minutes") || undefined,
    hint_policy: formData.get("hint_policy"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase.from("quizzes").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    passing_score: parsed.data.passing_score,
    is_exam: parsed.data.is_exam,
    time_limit_minutes: parsed.data.time_limit_minutes ?? null,
    hint_policy: parsed.data.hint_policy,
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/quizzes");
  return { error: null };
}

export async function toggleQuizPublishedAction(quizId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("quizzes").update({ published }).eq("id", quizId);
  if (error) throw new Error(error.message);
  revalidatePath("/admin/quizzes");
  revalidatePath(`/admin/quizzes/${quizId}`);
}

export async function setQuizSkillsAction(quizId: string, skillIds: string[]) {
  await requireAdmin();
  const supabase = await createClient();
  const { error: deleteError } = await supabase.from("quiz_skills").delete().eq("quiz_id", quizId);
  if (deleteError) throw new Error(deleteError.message);
  if (skillIds.length > 0) {
    const { error: insertError } = await supabase
      .from("quiz_skills")
      .insert(skillIds.map((skill_id) => ({ quiz_id: quizId, skill_id })));
    if (insertError) throw new Error(insertError.message);
  }
  revalidatePath(`/admin/quizzes/${quizId}`);
}

// ---- Questions + choices ----------------------------------------------------
//
// Called directly (not via <form action>) so we can pass a structured array
// of choices in one atomic operation instead of parsing indexed FormData
// field names.

export interface ChoiceInput {
  text: string;
  isCorrect: boolean;
}

export async function createQuestionAction(
  quizId: string,
  questionText: string,
  questionType: QuestionType,
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
    .from("quiz_questions")
    .insert({ quiz_id: quizId, question_text: trimmedText, question_type: questionType })
    .select("id")
    .single();
  if (questionError || !question) throw new Error(questionError?.message ?? "Failed to create question.");

  const { error: choicesError } = await supabase.from("quiz_choices").insert(
    validChoices.map((c, i) => ({
      question_id: question.id,
      choice_text: c.text,
      is_correct: c.isCorrect,
      order_index: i,
    })),
  );
  if (choicesError) throw new Error(choicesError.message);

  revalidatePath(`/admin/quizzes/${quizId}`);
}

export async function deleteQuestionAction(quizId: string, questionId: string) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("quiz_questions").delete().eq("id", questionId);
  if (error) throw new Error(error.message);
  revalidatePath(`/admin/quizzes/${quizId}`);
}
