import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { ctfEventStatus } from "@/lib/ctf/event-status";

export const metadata: Metadata = { title: "CTF Challenges" };

const STATUS_LABELS = { upcoming: "Upcoming", live: "Live", ended: "Ended" } as const;
const STATUS_CLASSES = {
  upcoming: "bg-accent-muted text-accent",
  live: "bg-success-muted text-success",
  ended: "bg-background-subtle text-foreground-subtle",
} as const;

export default async function CtfListPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: challenges }, { data: solved }, { data: events }] = await Promise.all([
    supabase
      .from("ctf_challenges_public")
      .select("id, event_id, title, category, difficulty, points")
      .eq("published", true)
      .order("points"),
    supabase.from("ctf_submissions").select("challenge_id").eq("user_id", user.id).eq("correct", true),
    supabase.from("ctf_events").select("id, slug, title, starts_at, ends_at").eq("published", true).order("starts_at"),
  ]);

  const solvedIds = new Set((solved ?? []).map((s) => s.challenge_id));
  const independentChallenges = (challenges ?? []).filter((c) => !c.event_id);

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">CTF Challenges</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Independent, unguided challenges. Solving one records real &quot;ctf&quot; skill evidence.
      </p>

      {events && events.length > 0 && (
        <div className="mb-8">
          <h2 className="mb-3 text-sm font-semibold text-foreground">Events</h2>
          <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
            {events.map((e) => {
              const status = ctfEventStatus(e.starts_at, e.ends_at);
              return (
                <li key={e.id}>
                  <Link
                    href={`/ctf/events/${e.id}`}
                    className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
                  >
                    <p className="text-sm font-medium text-foreground">{e.title}</p>
                    <span className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${STATUS_CLASSES[status]}`}>
                      {STATUS_LABELS[status]}
                    </span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      )}

      <h2 className="mb-3 text-sm font-semibold text-foreground">Independent challenges</h2>
      {independentChallenges.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {independentChallenges.map((c) => (
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
          No independent challenges are published yet.
        </div>
      )}
    </div>
  );
}
