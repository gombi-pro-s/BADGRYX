import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export default async function LearnPathPage({
  params,
}: {
  params: Promise<{ pathId: string }>;
}) {
  const { pathId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

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
      <h1 className="mb-1 text-2xl font-semibold text-foreground">{path.title}</h1>
      {path.description && <p className="mb-8 text-sm text-foreground-muted">{path.description}</p>}

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
                {moduleLessons.map((lesson) => (
                  <li key={lesson.id}>
                    <Link
                      href={`/learn/${path.id}/${mod.id}/${lesson.id}`}
                      className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
                    >
                      <span className="text-sm font-medium text-foreground">{lesson.title}</span>
                      <span className="shrink-0 text-xs text-foreground-subtle">
                        {completedLessonIds.has(lesson.id) ? (
                          <span className="text-success">Read</span>
                        ) : (
                          `${lesson.estimated_minutes} min`
                        )}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            </section>
          );
        })}
      </div>
    </div>
  );
}
