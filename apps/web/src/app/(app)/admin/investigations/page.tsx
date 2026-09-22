import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateInvestigationForm } from "./create-investigation-form";

export const metadata: Metadata = { title: "Investigations" };

export default async function AdminInvestigationsPage() {
  const supabase = await createClient();
  const { data: investigations } = await supabase
    .from("investigations")
    .select("id, slug, title, category, difficulty, published")
    .order("title");

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">Investigations</h2>

      {investigations && investigations.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {investigations.map((investigation) => (
            <li key={investigation.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/investigations/${investigation.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {investigation.title}
                </Link>
                <p className="mt-0.5 text-xs text-foreground-subtle">
                  {investigation.category} &middot; {investigation.difficulty}
                </p>
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  investigation.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {investigation.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No investigations yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New investigation</h3>
        <CreateInvestigationForm />
      </div>
    </div>
  );
}
