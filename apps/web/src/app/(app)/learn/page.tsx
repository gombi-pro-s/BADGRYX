import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Learn" };

export default async function LearnPage() {
  const supabase = await createClient();
  const { data: paths } = await supabase
    .from("learning_paths")
    .select("id, title, description")
    .eq("published", true)
    .order("order_index");

  return (
    <div className="mx-auto max-w-5xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Learn</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Structured paths from theory through practice. Reading a lesson gets you to
        &quot;Learning&quot; on the Skill Graph -- passing its comprehension check is what actually
        counts as evidence.
      </p>

      {paths && paths.length > 0 ? (
        <div className="grid gap-4 sm:grid-cols-2">
          {paths.map((path) => (
            <Link
              key={path.id}
              href={`/learn/${path.id}`}
              className="rounded-lg border border-border bg-surface p-5 transition-colors hover:border-border-strong"
            >
              <p className="text-sm font-semibold text-foreground">{path.title}</p>
              {path.description && (
                <p className="mt-1.5 text-sm text-foreground-muted">{path.description}</p>
              )}
            </Link>
          ))}
        </div>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No learning paths are published yet.
        </div>
      )}
    </div>
  );
}
