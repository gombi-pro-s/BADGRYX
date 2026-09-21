import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Labs" };

export default async function LabsListPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: labs }, { data: progress }] = await Promise.all([
    supabase
      .from("labs")
      .select("id, title, category, difficulty, points")
      .eq("published", true)
      .order("title"),
    supabase.from("lab_progress").select("lab_id, status").eq("user_id", user.id),
  ]);

  const statusByLab = new Map((progress ?? []).map((p) => [p.lab_id, p.status]));

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Labs</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Completing a lab guided records &quot;guided_lab&quot; evidence; completing it unguided
        records &quot;unguided_lab&quot; evidence and moves the skill to Demonstrated.
      </p>

      {labs && labs.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {labs.map((lab) => (
            <li key={lab.id}>
              <Link href={`/labs/${lab.id}`} className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle">
                <div>
                  <p className="text-sm font-medium text-foreground">{lab.title}</p>
                  <p className="mt-0.5 text-xs text-foreground-subtle">
                    {lab.category} &middot; {lab.difficulty} &middot; {lab.points} pts
                  </p>
                </div>
                {statusByLab.get(lab.id) === "completed" && (
                  <span className="shrink-0 text-xs font-medium text-success">Completed</span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No labs are published yet.
        </div>
      )}
    </div>
  );
}
