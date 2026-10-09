import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { getLocale } from "@/lib/i18n/cookie";
import { pickLessonText, pickPathText } from "@/lib/i18n/content-translation";

export default async function LearnPathPage({
  params,
}: {
  params: Promise<{ pathId: string }>;
}) {
  const { pathId } = await params;
  const user = await requireUser();
  const supabase = await createClient();
  const locale = await getLocale();

  const [{ data: path }, { data: modules }, { data: lessons }, { data: progress }] = await Promise.all([
    supabase.from("learning_paths").select("id, title, description").eq("id", pathId).eq("published", true).single(),
    supabase
      .from("modules")
      .select("id, title, order_index")
      .eq("path_id", pathId)
      .eq("published", true)
      .order("order_index"),
    supabase
      .from("lessons")
      .select("id, module_id, title, order_index, estimated_minutes")
      .eq("published", true)
      .order("order_index"),
    supabase.from("lesson_progress").select("lesson_id, completed_at").eq("user_id", user.id),
  ]);

  if (!path) notFound();

  const [{ data: pathTranslation }, { data: lessonTranslations }] = await Promise.all([
    supabase.from("learning_path_translations").select("locale, title, description").eq("path_id", path.id).eq("locale", "es").maybeSingle(),
    lessons && lessons.length > 0
      ? supabase
          .from("lesson_translations")
          .select("lesson_id, locale, title, content_markdown")
          .in("locale", ["es"])
          .in(
            "lesson_id",
            lessons.map((l) => l.id),
          )
      : Promise.resolve({ data: [] as { lesson_id: string; locale: string; title: string; content_markdown: string }[] }),
  ]);
  const pathText = pickPathText(path, pathTranslation ? [pathTranslation] : [], locale);
  const lessonTranslationsByLessonId = new Map<string, typeof lessonTranslations>();
  for (const t of lessonTranslations ?? []) {
    const existing = lessonTranslationsByLessonId.get(t.lesson_id) ?? [];
    existing.push(t);
    lessonTranslationsByLessonId.set(t.lesson_id, existing);
  }

  const completedLessonIds = new Set(
    (progress ?? []).filter((p) => p.completed_at).map((p) => p.lesson_id),
  );
  const lessonsByModule = new Map<string, typeof lessons>();
  for (const lesson of lessons ?? []) {
    const list = lessonsByModule.get(lesson.module_id) ?? [];
    list.push(lesson);
    lessonsByModule.set(lesson.module_id, list);
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">{pathText.title}</h1>
      {pathText.description && <p className="mb-8 text-sm text-foreground-muted">{pathText.description}</p>}

      <div className="space-y-6">
        {(modules ?? []).map((mod) => {
          const moduleLessons = lessonsByModule.get(mod.id) ?? [];
          if (moduleLessons.length === 0) return null;
          return (
            <section key={mod.id}>
              <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-foreground-subtle">
                {mod.title}
              </h2>
              <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
                {moduleLessons.map((lesson) => {
                  const lessonText = pickLessonText(
                    { title: lesson.title, content_markdown: "" },
                    lessonTranslationsByLessonId.get(lesson.id) ?? [],
                    locale,
                  );
                  return (
                    <li key={lesson.id}>
                      <Link
                        href={`/learn/${path.id}/${mod.id}/${lesson.id}`}
                        className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
                      >
                        <span className="text-sm font-medium text-foreground">{lessonText.title}</span>
                        <span className="shrink-0 text-xs text-foreground-subtle">
                          {completedLessonIds.has(lesson.id) ? (
                            <span className="text-success">Read</span>
                          ) : (
                            `${lesson.estimated_minutes} min`
                          )}
                        </span>
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </section>
          );
        })}
      </div>
    </div>
  );
}
