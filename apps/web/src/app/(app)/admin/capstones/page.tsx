import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateCapstoneForm } from "./create-capstone-form";

export const metadata: Metadata = { title: "Capstones" };

export default async function AdminCapstonesPage() {
  const supabase = await createClient();
  const { data: capstones } = await supabase
    .from("capstones")
    .select("id, slug, title, report_required, published")
    .order("title");

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">Capstones</h2>

      {capstones && capstones.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {capstones.map((capstone) => (
            <li key={capstone.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/capstones/${capstone.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {capstone.title}
                </Link>
                <p className="mt-0.5 text-xs text-foreground-subtle">
                  {capstone.slug} {capstone.report_required && <>&middot; report required</>}
                </p>
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  capstone.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {capstone.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No capstones yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New capstone</h3>
        <CreateCapstoneForm />
      </div>
    </div>
  );
}
