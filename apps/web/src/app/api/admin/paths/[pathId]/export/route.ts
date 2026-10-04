import { NextResponse } from "next/server";
import { requireApiUser } from "@/lib/auth/api";
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
 * /admin/paths/import (or, from mobile, POST /api/admin/paths/import --
 * see ADR 0058). Labs and CTF challenges are intentionally excluded:
 * they have no real FK linking them to a path (only an informal shared-
 * skill-tag convention), and lab/CTF flags are stored only as a hash, so
 * "export" would either invent a path-membership convention this schema
 * doesn't have, or silently omit the one field (the flag) that makes the
 * exported content actually usable.
 *
 * Lives under `/api/admin/...` rather than its original
 * `/admin/paths/[pathId]/export` -- moved here specifically because
 * `/admin` is one of `lib/supabase/middleware.ts`'s `PROTECTED_PREFIXES`:
 * that proxy redirects an unauthenticated *browser* request to `/login`
 * before any Route Handler under it ever runs, using only the cookie
 * session, with no knowledge of a Bearer header. A mobile caller with no
 * cookie would always get redirected to an HTML login page instead of
 * this route's own `requireApiUser()` ever getting a chance to return
 * its 401 JSON. `/api/*` isn't in that prefix list, so this route (like
 * every other mobile-facing Route Handler in this app) is reachable
 * by Bearer token alone. The web admin UI's own "Export" link was
 * updated to this new URL; a logged-in admin's browser still works via
 * the same cookie session either way.
 *
 * Uses `requireApiUser()` rather than `requireAdmin()` so the mobile app
 * can call this directly with a Bearer token, same as every other
 * mobile-facing Route Handler in this app (see ADR 0033) -- RLS
 * (`learning_paths_select_published_or_staff` etc.) is still the real
 * boundary: a non-staff caller's read simply comes back empty for
 * unpublished content, exactly as a direct Postgrest read would.
 */
export async function GET(request: Request, { params }: { params: Promise<{ pathId: string }> }) {
  const auth = await requireApiUser(request);
  if ("unauthorized" in auth) return auth.unauthorized;
  const { supabase } = auth;
  const { pathId } = await params;

  const { data: path } = await supabase
    .from("learning_paths")
    .select("slug, title, description, cover_image_url, published")
    .eq("id", pathId)
    .single();
  if (!path) return NextResponse.json({ error: "Learning path not found." }, { status: 404 });

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
