import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreatePathForm } from "./create-path-form";

export const metadata: Metadata = { title: "Learning Paths" };

export default async function AdminPathsPage() {
  const supabase = await createClient();
  const { data: paths } = await supabase
    .from("learning_paths")
    .select("id, slug, title, published, order_index")
    .order("order_index");

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">Learning Paths</h2>

      {paths && paths.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {paths.map((p) => (
            <li key={p.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/paths/${p.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {p.title}
                </Link>
                <p className="mt-0.5 text-xs text-foreground-subtle">/{p.slug}</p>
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  p.published
                    ? "bg-success-muted text-success"
                    : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {p.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No learning paths yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New learning path</h3>
        <CreatePathForm />
      </div>
    </div>
  );
}
