import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getLocale } from "@/lib/i18n/cookie";
import { pickPathText } from "@/lib/i18n/content-translation";

export const metadata: Metadata = { title: "Learn" };

export default async function LearnPage() {
  const supabase = await createClient();
  const locale = await getLocale();
  const { data: paths } = await supabase
    .from("learning_paths")
    .select("id, title, description")
    .eq("published", true)
    .order("order_index");

  // A second round-trip rather than a join: learning_path_translations'
  // own RLS (mirroring learning_paths_select_published_or_staff through
  // the parent row) already scopes this to exactly the rows above, so an
  // `.in()` on their ids is just an efficiency filter, not a security
  // boundary. See ADR 0064.
  const { data: translations } =
    paths && paths.length > 0
      ? await supabase
          .from("learning_path_translations")
          .select("path_id, locale, title, description")
          .in("path_id", paths.map((p) => p.id))
      : { data: [] };
  const translationsByPathId = new Map<string, typeof translations>();
  for (const t of translations ?? []) {
    const existing = translationsByPathId.get(t.path_id) ?? [];
    existing.push(t);
    translationsByPathId.set(t.path_id, existing);
  }

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
          {paths.map((path) => {
            const text = pickPathText(path, translationsByPathId.get(path.id) ?? [], locale);
            return (
              <Link
                key={path.id}
                href={`/learn/${path.id}`}
                className="rounded-lg border border-border bg-surface p-5 transition-colors hover:border-border-strong"
              >
                <p className="text-sm font-semibold text-foreground">{text.title}</p>
                {text.description && (
                  <p className="mt-1.5 text-sm text-foreground-muted">{text.description}</p>
                )}
              </Link>
            );
          })}
        </div>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No learning paths are published yet.
        </div>
      )}
    </div>
  );
}
