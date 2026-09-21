import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateLabForm } from "./create-lab-form";

export const metadata: Metadata = { title: "Labs" };

export default async function AdminLabsPage() {
  const supabase = await createClient();
  const { data: labs } = await supabase
    .from("labs")
    .select("id, slug, title, category, difficulty, published")
    .order("title");

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">Labs</h2>

      {labs && labs.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {labs.map((lab) => (
            <li key={lab.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/labs/${lab.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {lab.title}
                </Link>
                <p className="mt-0.5 text-xs text-foreground-subtle">
                  {lab.category} &middot; {lab.difficulty}
                </p>
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  lab.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {lab.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No labs yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New lab</h3>
        <CreateLabForm />
      </div>
    </div>
  );
}
