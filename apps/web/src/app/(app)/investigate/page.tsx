import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Investigations" };

export default async function InvestigationsListPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: investigations }, { data: submissions }] = await Promise.all([
    supabase
      .from("investigations")
      .select("id, title, category, difficulty, estimated_minutes, points")
      .eq("published", true)
      .order("title"),
    supabase.from("investigation_submissions").select("investigation_id, passed, score").eq("user_id", user.id),
  ]);

  const bestByInvestigation = new Map<string, { passed: boolean; score: number }>();
  for (const s of submissions ?? []) {
    const current = bestByInvestigation.get(s.investigation_id);
    if (!current || s.score > current.score) bestByInvestigation.set(s.investigation_id, s);
  }

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Investigations</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Real case files -- WHOIS records, email headers, log excerpts, and more. Review the evidence and answer
        what actually happened. Graded deterministically, server-side, the same as every quiz or lab here.
      </p>

      {investigations && investigations.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {investigations.map((investigation) => {
            const best = bestByInvestigation.get(investigation.id);
            return (
              <li key={investigation.id}>
                <Link
                  href={`/investigate/${investigation.id}`}
                  className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
                >
                  <div>
                    <p className="text-sm font-medium text-foreground">{investigation.title}</p>
                    <p className="text-xs text-foreground-subtle">
                      {investigation.category} &middot; {investigation.difficulty} &middot; {investigation.estimated_minutes} min &middot;{" "}
                      {investigation.points} pts
                    </p>
                  </div>
                  {best && (
                    <span
                      className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                        best.passed ? "bg-success-muted text-success" : "bg-warning-muted text-warning"
                      }`}
                    >
                      {best.passed ? "Solved" : `Best: ${best.score}%`}
                    </span>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No investigations published yet.
        </div>
      )}
    </div>
  );
}
