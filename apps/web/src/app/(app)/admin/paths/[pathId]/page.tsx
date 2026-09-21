import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { togglePathPublishedAction } from "../actions";
import { CreateModuleForm } from "./create-module-form";
import { EditPathForm } from "./edit-path-form";

export default async function AdminPathDetailPage({
  params,
}: {
  params: Promise<{ pathId: string }>;
}) {
  const { pathId } = await params;
  const supabase = await createClient();

  const [{ data: path }, { data: modules }] = await Promise.all([
    supabase.from("learning_paths").select("id, slug, title, description, published").eq("id", pathId).single(),
    supabase.from("modules").select("id, slug, title, published, order_index").eq("path_id", pathId).order("order_index"),
  ]);

  if (!path) notFound();

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{path.title}</h2>
        <PublishToggle
          published={path.published}
          onToggle={togglePathPublishedAction.bind(null, path.id)}
        />
      </div>

      <div className="mb-8 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Path details</h3>
        <EditPathForm pathId={path.id} initial={{ slug: path.slug, title: path.title, description: path.description ?? "" }} />
      </div>

      <h3 className="mb-3 text-sm font-semibold text-foreground">Modules</h3>
      {modules && modules.length > 0 ? (
        <ul className="mb-6 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {modules.map((m) => (
            <li key={m.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <Link href={`/admin/paths/${path.id}/${m.id}`} className="text-sm font-medium text-foreground hover:underline">
                {m.title}
              </Link>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  m.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {m.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-6 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No modules yet.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New module</h3>
        <CreateModuleForm pathId={path.id} />
      </div>
    </div>
  );
}
