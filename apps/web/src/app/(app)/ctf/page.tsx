import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "CTF Challenges" };

export default async function CtfListPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: challenges }, { data: solved }] = await Promise.all([
    supabase
      .from("ctf_challenges_public")
      .select("id, title, category, difficulty, points")
      .eq("published", true)
      .order("points"),
    supabase.from("ctf_submissions").select("challenge_id").eq("user_id", user.id).eq("correct", true),
  ]);

  const solvedIds = new Set((solved ?? []).map((s) => s.challenge_id));

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">CTF Challenges</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Independent, unguided challenges. Solving one records real &quot;ctf&quot; skill evidence.
      </p>

      {challenges && challenges.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {challenges.map((c) => (
            <li key={c.id}>
              <Link href={`/ctf/${c.id}`} className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle">
                <div>
                  <p className="text-sm font-medium text-foreground">{c.title}</p>
                  <p className="mt-0.5 text-xs text-foreground-subtle">
                    {c.category} &middot; {c.difficulty} &middot; {c.points} pts
                  </p>
                </div>
                {solvedIds.has(c.id) && <span className="shrink-0 text-xs font-medium text-success">Solved</span>}
              </Link>
            </li>
          ))}
        </ul>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No challenges are published yet.
        </div>
      )}
    </div>
  );
}
