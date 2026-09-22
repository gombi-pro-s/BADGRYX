import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import type { CapstoneStatus } from "@/types/database";

export const metadata: Metadata = { title: "Capstones" };

const STATUS_LABEL: Record<CapstoneStatus, string> = {
  submitted: "Submitted",
  under_review: "Under review",
  passed: "Passed",
  needs_revision: "Needs revision",
};
const STATUS_CLASS: Record<CapstoneStatus, string> = {
  submitted: "bg-background-subtle text-foreground-subtle",
  under_review: "bg-warning-muted text-warning",
  passed: "bg-success-muted text-success",
  needs_revision: "bg-danger-muted text-danger",
};

export default async function CapstonesPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: capstones }, { data: submissions }] = await Promise.all([
    supabase.from("capstones").select("id, title, description, report_required").eq("published", true).order("title"),
    supabase
      .from("capstone_submissions")
      .select("capstone_id, status, submitted_at")
      .eq("user_id", user.id)
      .order("submitted_at", { ascending: false }),
  ]);

  // Most recent submission per capstone (submissions arrive newest-first).
  const latestByCapstone = new Map<string, CapstoneStatus>();
  for (const s of submissions ?? []) {
    if (!latestByCapstone.has(s.capstone_id)) latestByCapstone.set(s.capstone_id, s.status);
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Capstones</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Real, comprehensive projects staff review by hand -- not autograded. A passed capstone is independent
        proof of ability, same weight as an unguided lab or CTF solve in your Skill Graph.
      </p>

      {capstones && capstones.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {capstones.map((capstone) => {
            const status = latestByCapstone.get(capstone.id);
            return (
              <li key={capstone.id}>
                <Link
                  href={`/capstones/${capstone.id}`}
                  className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-foreground">{capstone.title}</p>
                    {capstone.description && (
                      <p className="mt-0.5 truncate text-xs text-foreground-subtle">{capstone.description}</p>
                    )}
                  </div>
                  {status && (
                    <span className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${STATUS_CLASS[status]}`}>
                      {STATUS_LABEL[status]}
                    </span>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No capstones published yet.
        </div>
      )}
    </div>
  );
}
