import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateEventForm } from "./create-event-form";

export const metadata: Metadata = { title: "CTF Events" };

export default async function AdminCtfEventsPage() {
  const supabase = await createClient();
  const { data: events } = await supabase
    .from("ctf_events")
    .select("id, slug, title, published, starts_at, ends_at")
    .order("created_at", { ascending: false });

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">CTF Events</h2>
      <p className="mb-4 text-sm text-foreground-muted">
        Group challenges under a timed event with a live leaderboard. A challenge with no event stays an
        independent challenge, listed separately on <code>/ctf</code>.
      </p>

      {events && events.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {events.map((e) => (
            <li key={e.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/ctf-events/${e.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {e.title}
                </Link>
                <p className="mt-0.5 text-xs text-foreground-subtle">/{e.slug}</p>
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  e.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {e.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No CTF events yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New event</h3>
        <CreateEventForm />
      </div>
    </div>
  );
}
