import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { EventStatusBanner } from "../event-status-banner";

export const metadata: Metadata = { title: "CTF Event" };

export default async function CtfEventDetailPage({ params }: { params: Promise<{ eventId: string }> }) {
  const { eventId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: event } = await supabase
    .from("ctf_events")
    .select("id, title, description, starts_at, ends_at")
    .eq("id", eventId)
    .maybeSingle();
  if (!event) notFound();

  const [{ data: challenges }, { data: solved }, { data: leaderboard }] = await Promise.all([
    supabase
      .from("ctf_challenges_public")
      .select("id, title, category, difficulty, points")
      .eq("event_id", eventId)
      .order("points"),
    supabase.from("ctf_submissions").select("challenge_id").eq("user_id", user.id).eq("correct", true),
    supabase.rpc("ctf_event_leaderboard", { p_event_id: eventId }),
  ]);

  const solvedIds = new Set((solved ?? []).map((s) => s.challenge_id));

  return (
    <div className="mx-auto max-w-4xl px-6 py-10">
      <Link href="/ctf" className="mb-4 inline-block text-sm text-foreground-muted hover:underline">
        &larr; Back to CTF
      </Link>
      <h1 className="mb-1 text-2xl font-semibold text-foreground">{event.title}</h1>
      {event.description && <p className="mb-4 text-sm text-foreground-muted">{event.description}</p>}

      <div className="mb-8">
        <EventStatusBanner startsAt={event.starts_at} endsAt={event.ends_at} />
      </div>

      <div className="grid gap-8 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <h2 className="mb-3 text-sm font-semibold text-foreground">Challenges</h2>
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
            <div className="rounded-lg border border-dashed border-border bg-surface p-6 text-center text-sm text-foreground-muted">
              No challenges published yet.
            </div>
          )}
        </div>

        <div>
          <h2 className="mb-3 text-sm font-semibold text-foreground">Leaderboard</h2>
          {leaderboard && leaderboard.length > 0 ? (
            <ol className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
              {leaderboard.map((row, i) => (
                <li
                  key={row.user_id}
                  className={`flex items-center justify-between gap-3 px-3 py-2 text-sm ${
                    row.user_id === user.id ? "bg-accent-muted" : ""
                  }`}
                >
                  <span className="min-w-0 truncate text-foreground">
                    <span className="mr-2 text-foreground-subtle">#{i + 1}</span>
                    {row.display_name}
                  </span>
                  <span className="shrink-0 font-medium text-foreground">{row.total_points}</span>
                </li>
              ))}
            </ol>
          ) : (
            <div className="rounded-lg border border-dashed border-border bg-surface p-4 text-center text-xs text-foreground-muted">
              No solves yet -- be the first.
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
