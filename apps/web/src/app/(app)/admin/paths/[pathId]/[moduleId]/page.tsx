import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../../publish-toggle";
import { toggleModulePublishedAction } from "../../actions";
import { CreateLessonForm } from "./create-lesson-form";

export default async function AdminModuleDetailPage({
  params,
}: {
  params: Promise<{ pathId: string; moduleId: string }>;
}) {
  const { pathId, moduleId } = await params;
  const supabase = await createClient();

  const [{ data: path }, { data: mod }, { data: lessons }] = await Promise.all([
    supabase.from("learning_paths").select("id, title").eq("id", pathId).single(),
    supabase.from("modules").select("id, title, published").eq("id", moduleId).single(),
    supabase
      .from("lessons")
      .select("id, slug, title, published, order_index")
      .eq("module_id", moduleId)
      .order("order_index"),
  ]);

  if (!path || !mod) notFound();

  return (
    <div>
      <Link href={`/admin/paths/${pathId}`} className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; {path.title}
      </Link>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{mod.title}</h2>
        <PublishToggle
          published={mod.published}
          onToggle={toggleModulePublishedAction.bind(null, pathId, mod.id)}
        />
      </div>

      <h3 className="mb-3 text-sm font-semibold text-foreground">Lessons</h3>
      {lessons && lessons.length > 0 ? (
        <ul className="mb-6 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {lessons.map((l) => (
            <li key={l.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <Link
                href={`/admin/paths/${pathId}/${moduleId}/${l.id}`}
                className="text-sm font-medium text-foreground hover:underline"
              >
                {l.title}
              </Link>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  l.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {l.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-6 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No lessons yet.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New lesson</h3>
        <CreateLessonForm pathId={pathId} moduleId={moduleId} />
      </div>
    </div>
  );
}
