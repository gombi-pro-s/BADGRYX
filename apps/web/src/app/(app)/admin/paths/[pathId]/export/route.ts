import { NextResponse } from "next/server";
import { notFound } from "next/navigation";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { PATH_BUNDLE_FORMAT, type PathBundle } from "@/lib/content-io/path-bundle";
import type { HintPolicy, QuestionType } from "@/types/database";

interface ExportedChoice {
  choice_text: string;
  is_correct: boolean;
}

interface ExportedQuestion {
  question_text: string;
  question_type: QuestionType;
  points: number;
  choices: ExportedChoice[];
}

interface ExportedQuiz {
  id: string;
  lesson_id: string | null;
  slug: string;
  title: string;
  passing_score: number;
  max_attempts: number | null;
  is_exam: boolean;
  time_limit_minutes: number | null;
  hint_policy: HintPolicy;
  published: boolean;
}

interface ExportedLesson {
  id: string;
  module_id: string;
  slug: string;
  title: string;
  summary: string | null;
  content_markdown: string;
  estimated_minutes: number;
  published: boolean;
}

/**
 * Exports a learning path (path -> modules -> lessons -> quiz -> questions
 * -> choices, skill tags by slug) as a bundle importable by
 * /admin/paths/import. Labs and CTF challenges are intentionally excluded:
 * they have no real FK linking them to a path (only an informal shared-
 * skill-tag convention), and lab/CTF flags are stored only as a hash, so
 * "export" would either invent a path-membership convention this schema
 * doesn't have, or silently omit the one field (the flag) that makes the
 * exported content actually usable.
 */
export async function GET(_request: Request, { params }: { params: Promise<{ pathId: string }> }) {
  await requireAdmin();
  const { pathId } = await params;
  const supabase = await createClient();

  const { data: path } = await supabase
    .from("learning_paths")
    .select("slug, title, description, cover_image_url, published")
    .eq("id", pathId)
    .single();
  if (!path) notFound();

  const { data: modules } = await supabase
    .from("modules")
    .select("id, slug, title, description, published")
    .eq("path_id", pathId)
    .order("order_index");

  const moduleIds = (modules ?? []).map((m) => m.id);
  const { data: lessons } = moduleIds.length
    ? await supabase
        .from("lessons")
        .select("id, module_id, slug, title, summary, content_markdown, estimated_minutes, published")
        .in("module_id", moduleIds)
        .order("order_index")
    : { data: [] };

  const lessonIds = (lessons ?? []).map((l) => l.id);

  const [{ data: lessonSkillRows }, { data: quizzes }] = await Promise.all([
    lessonIds.length
      ? supabase.from("lesson_skills").select("lesson_id, skills(slug)").in("lesson_id", lessonIds)
      : Promise.resolve({ data: [] }),
    lessonIds.length
      ? supabase
          .from("quizzes")
          .select(
            "id, lesson_id, slug, title, passing_score, max_attempts, is_exam, time_limit_minutes, hint_policy, published",
          )
          .in("lesson_id", lessonIds)
      : Promise.resolve({ data: [] }),
  ]);

  const quizIds = (quizzes ?? []).map((q) => q.id);
  const [{ data: quizSkillRows }, { data: questions }] = await Promise.all([
    quizIds.length
      ? supabase.from("quiz_skills").select("quiz_id, skills(slug)").in("quiz_id", quizIds)
      : Promise.resolve({ data: [] }),
    quizIds.length
      ? supabase
          .from("quiz_questions")
          .select("id, quiz_id, question_text, question_type, points")
          .in("quiz_id", quizIds)
          .order("order_index")
      : Promise.resolve({ data: [] }),
  ]);

  const questionIds = (questions ?? []).map((q) => q.id);
  const { data: choices } = questionIds.length
    ? await supabase
        .from("quiz_choices")
        .select("question_id, choice_text, is_correct")
        .in("question_id", questionIds)
        .order("order_index")
    : { data: [] };

  interface SkillTagRow {
    skills: { slug: string } | null;
  }

  function groupSkillSlugs<T extends SkillTagRow>(rows: T[] | null, idOf: (row: T) => string) {
    const map = new Map<string, string[]>();
    for (const row of rows ?? []) {
      const slug = row.skills?.slug;
      if (!slug) continue;
      const key = idOf(row);
      const list = map.get(key) ?? [];
      list.push(slug);
      map.set(key, list);
    }
    return map;
  }
  const skillSlugsByLesson = groupSkillSlugs(
    lessonSkillRows as ({ lesson_id: string } & SkillTagRow)[] | null,
    (row) => row.lesson_id,
  );
  const skillSlugsByQuiz = groupSkillSlugs(
    quizSkillRows as ({ quiz_id: string } & SkillTagRow)[] | null,
    (row) => row.quiz_id,
  );

  const choicesByQuestion = new Map<string, ExportedChoice[]>();
  for (const c of choices ?? []) {
    const list = choicesByQuestion.get(c.question_id) ?? [];
    list.push({ choice_text: c.choice_text, is_correct: c.is_correct });
    choicesByQuestion.set(c.question_id, list);
  }

  const questionsByQuiz = new Map<string, ExportedQuestion[]>();
  for (const q of questions ?? []) {
    const list = questionsByQuiz.get(q.quiz_id) ?? [];
    list.push({
      question_text: q.question_text,
      question_type: q.question_type,
      points: q.points,
      choices: choicesByQuestion.get(q.id) ?? [],
    });
    questionsByQuiz.set(q.quiz_id, list);
  }

  const quizByLesson = new Map<string, ExportedQuiz>();
  for (const q of (quizzes ?? []) as ExportedQuiz[]) {
    if (q.lesson_id) quizByLesson.set(q.lesson_id, q);
  }

  const lessonsByModule = new Map<string, ExportedLesson[]>();
  for (const l of (lessons ?? []) as ExportedLesson[]) {
    const list = lessonsByModule.get(l.module_id) ?? [];
    list.push(l);
    lessonsByModule.set(l.module_id, list);
  }

  const bundle: PathBundle = {
    format: PATH_BUNDLE_FORMAT,
    path: {
      slug: path.slug,
      title: path.title,
      description: path.description ?? undefined,
      cover_image_url: path.cover_image_url ?? undefined,
      published: path.published,
    },
    modules: (modules ?? []).map((m) => ({
      slug: m.slug,
      title: m.title,
      description: m.description ?? undefined,
      published: m.published,
      lessons: (lessonsByModule.get(m.id) ?? []).map((l) => {
        const quiz = quizByLesson.get(l.id);
        return {
          slug: l.slug,
          title: l.title,
          summary: l.summary ?? undefined,
          content_markdown: l.content_markdown,
          estimated_minutes: l.estimated_minutes,
          published: l.published,
          skill_slugs: skillSlugsByLesson.get(l.id) ?? [],
          quiz: quiz
            ? {
                slug: quiz.slug,
                title: quiz.title,
                passing_score: quiz.passing_score,
                max_attempts: quiz.max_attempts ?? undefined,
                is_exam: quiz.is_exam,
                time_limit_minutes: quiz.time_limit_minutes ?? undefined,
                hint_policy: quiz.hint_policy,
                published: quiz.published,
                skill_slugs: skillSlugsByQuiz.get(quiz.id) ?? [],
                questions: questionsByQuiz.get(quiz.id) ?? [],
              }
            : undefined,
        };
      }),
    })),
  };

  return new NextResponse(JSON.stringify(bundle, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Content-Disposition": `attachment; filename="${path.slug}.icorepen-path.json"`,
    },
  });
}
