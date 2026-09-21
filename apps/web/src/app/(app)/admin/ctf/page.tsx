import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateChallengeForm } from "./create-challenge-form";

export const metadata: Metadata = { title: "CTF Challenges" };

export default async function AdminCtfPage() {
  const supabase = await createClient();
  const { data: challenges } = await supabase
    .from("ctf_challenges")
    .select("id, slug, title, category, difficulty, points, published")
    .order("title");

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">CTF Challenges</h2>

      {challenges && challenges.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {challenges.map((c) => (
            <li key={c.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/ctf/${c.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {c.title}
                </Link>
                <p className="mt-0.5 text-xs text-foreground-subtle">
                  {c.category} &middot; {c.difficulty} &middot; {c.points} pts
                </p>
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  c.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {c.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No challenges yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New challenge</h3>
        <CreateChallengeForm />
      </div>
    </div>
  );
}
