"use server";

import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { logAuditEvent } from "@/lib/audit";
import { parsePathBundle, type LessonBundle, type ModuleBundle, type QuizBundle } from "@/lib/content-io/path-bundle";

export interface ImportFormState {
  error: string | null;
  importedPathId: string | null;
  importedSlug: string | null;
  warnings: string[];
}

export const initialImportState: ImportFormState = {
  error: null,
  importedPathId: null,
  importedSlug: null,
  warnings: [],
};

/**
 * Imports a learning-path bundle (see lib/content-io/path-bundle.ts) as a
 * new learning path. There's no multi-statement transaction across these
 * PostgREST calls, so a failure partway through is cleaned up manually: if
 * anything after the initial path insert fails, the path row is deleted,
 * which cascades to every module/lesson/quiz/question/choice already
 * created under it (all FKs in this hierarchy are ON DELETE CASCADE - see
 * ADR 0004) - the admin never has to hunt down a half-imported path by
 * hand.
 */
export async function importPathBundleAction(
  _prev: ImportFormState,
  formData: FormData,
): Promise<ImportFormState> {
  const admin = await requireAdmin();
  const raw = String(formData.get("bundle") ?? "");
  if (!raw.trim()) {
    return { ...initialImportState, error: "Paste or choose a bundle JSON file first." };
  }

  const parsed = parsePathBundle(raw);
  if (parsed.data === null) {
    return { ...initialImportState, error: parsed.error };
  }
  const bundle = parsed.data;

  const supabase = await createClient();
  const warnings: string[] = [];

  // Resolve every skill slug referenced anywhere in the bundle up front.
  // A slug this environment doesn't have is skipped (not fatal) - bulk
  // content moved from another environment may reference skills that
  // haven't been created here yet.
  const allSkillSlugs = new Set<string>();
  for (const m of bundle.modules) {
    for (const l of m.lessons) {
      l.skill_slugs.forEach((s) => allSkillSlugs.add(s));
      l.quiz?.skill_slugs.forEach((s) => allSkillSlugs.add(s));
    }
  }
  const skillIdBySlug = new Map<string, string>();
  if (allSkillSlugs.size > 0) {
    const { data: skillRows } = await supabase.from("skills").select("id, slug").in("slug", Array.from(allSkillSlugs));
    for (const row of skillRows ?? []) skillIdBySlug.set(row.slug, row.id);
    for (const slug of allSkillSlugs) {
      if (!skillIdBySlug.has(slug)) warnings.push(`Skill "${slug}" doesn't exist here - skipped that tag.`);
    }
  }

  function resolvedSkillIds(slugs: string[]) {
    return slugs.map((s) => skillIdBySlug.get(s)).filter((id): id is string => Boolean(id));
  }

  const { data: pathRow, error: pathError } = await supabase
    .from("learning_paths")
    .insert({
      slug: bundle.path.slug,
      title: bundle.path.title,
      description: bundle.path.description ?? null,
      cover_image_url: bundle.path.cover_image_url ?? null,
      published: bundle.path.published,
      created_by: admin.id,
    })
    .select("id")
    .single();
  if (pathError || !pathRow) {
    return {
      ...initialImportState,
      error: pathError?.code === "23505" ? "That path slug is already in use." : pathError?.message ?? "Import failed.",
    };
  }
  const pathId = pathRow.id;

  async function abort(message: string): Promise<ImportFormState> {
    await supabase.from("learning_paths").delete().eq("id", pathId);
    return { ...initialImportState, error: message };
  }

  async function importQuiz(lessonId: string, quiz: QuizBundle): Promise<string | null> {
    const { data: quizRow, error: quizError } = await supabase
      .from("quizzes")
      .insert({
        lesson_id: lessonId,
        slug: quiz.slug,
        title: quiz.title,
        passing_score: quiz.passing_score,
        max_attempts: quiz.max_attempts ?? null,
        is_exam: quiz.is_exam,
        time_limit_minutes: quiz.time_limit_minutes ?? null,
        hint_policy: quiz.hint_policy,
        published: quiz.published,
      })
      .select("id")
      .single();
    if (quizError || !quizRow) {
      return quizError?.code === "23505"
        ? `Quiz slug "${quiz.slug}" is already in use.`
        : quizError?.message ?? "Failed to create quiz.";
    }

    const quizSkillIds = resolvedSkillIds(quiz.skill_slugs);
    if (quizSkillIds.length > 0) {
      const { error } = await supabase
        .from("quiz_skills")
        .insert(quizSkillIds.map((skill_id) => ({ quiz_id: quizRow.id, skill_id })));
      if (error) return error.message;
    }

    for (const question of quiz.questions) {
      const { data: questionRow, error: questionError } = await supabase
        .from("quiz_questions")
        .insert({ quiz_id: quizRow.id, question_text: question.question_text, question_type: question.question_type, points: question.points })
        .select("id")
        .single();
      if (questionError || !questionRow) return questionError?.message ?? "Failed to create question.";

      const { error: choicesError } = await supabase.from("quiz_choices").insert(
        question.choices.map((c, i) => ({
          question_id: questionRow.id,
          choice_text: c.choice_text,
          is_correct: c.is_correct,
          order_index: i,
        })),
      );
      if (choicesError) return choicesError.message;
    }
    return null;
  }

  async function importLesson(moduleId: string, moduleSlug: string, lesson: LessonBundle): Promise<string | null> {
    const { data: lessonRow, error: lessonError } = await supabase
      .from("lessons")
      .insert({
        module_id: moduleId,
        slug: lesson.slug,
        title: lesson.title,
        summary: lesson.summary ?? null,
        content_markdown: lesson.content_markdown,
        estimated_minutes: lesson.estimated_minutes,
        published: lesson.published,
      })
      .select("id")
      .single();
    if (lessonError || !lessonRow) {
      return lessonError?.code === "23505"
        ? `Lesson slug "${lesson.slug}" already exists in module "${moduleSlug}".`
        : lessonError?.message ?? "Failed to create lesson.";
    }

    const lessonSkillIds = resolvedSkillIds(lesson.skill_slugs);
    if (lessonSkillIds.length > 0) {
      const { error } = await supabase
        .from("lesson_skills")
        .insert(lessonSkillIds.map((skill_id) => ({ lesson_id: lessonRow.id, skill_id })));
      if (error) return error.message;
    }

    if (lesson.quiz) {
      const quizError = await importQuiz(lessonRow.id, lesson.quiz);
      if (quizError) return quizError;
    }
    return null;
  }

  async function importModule(mod: ModuleBundle): Promise<string | null> {
    const { data: moduleRow, error: moduleError } = await supabase
      .from("modules")
      .insert({ path_id: pathId, slug: mod.slug, title: mod.title, description: mod.description ?? null, published: mod.published })
      .select("id")
      .single();
    if (moduleError || !moduleRow) {
      return moduleError?.code === "23505"
        ? `Module slug "${mod.slug}" already exists in this path.`
        : moduleError?.message ?? "Failed to create module.";
    }
    for (const lesson of mod.lessons) {
      const lessonError = await importLesson(moduleRow.id, mod.slug, lesson);
      if (lessonError) return `Module "${mod.slug}": ${lessonError}`;
    }
    return null;
  }

  for (const mod of bundle.modules) {
    const error = await importModule(mod);
    if (error) return abort(error);
  }

  await logAuditEvent(supabase, "learning_path.imported", "learning_path", pathId, undefined, {
    slug: bundle.path.slug,
    module_count: bundle.modules.length,
  });

  revalidatePath("/admin/paths");
  return { error: null, importedPathId: pathId, importedSlug: bundle.path.slug, warnings };
}
