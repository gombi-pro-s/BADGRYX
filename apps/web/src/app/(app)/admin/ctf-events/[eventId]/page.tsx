import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { toggleEventPublishedAction } from "../actions";
import { EditEventForm } from "./edit-event-form";

export default async function AdminCtfEventDetailPage({ params }: { params: Promise<{ eventId: string }> }) {
  const { eventId } = await params;
  const supabase = await createClient();

  const [{ data: event }, { data: challenges }] = await Promise.all([
    supabase
      .from("ctf_events")
      .select("id, slug, title, description, scoring_type, starts_at, ends_at, published")
      .eq("id", eventId)
      .maybeSingle(),
    supabase.from("ctf_challenges").select("id, title, published").eq("event_id", eventId).order("title"),
  ]);

  if (!event) notFound();

  return (
    <div>
      <Link href="/admin/ctf-events" className="mb-4 inline-block text-sm text-foreground-muted hover:underline">
        &larr; Back to events
      </Link>

      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{event.title}</h2>
        <PublishToggle published={event.published} onToggle={toggleEventPublishedAction.bind(null, event.id)} />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Event details</h3>
        <EditEventForm
          eventId={event.id}
          initial={{
            title: event.title,
            slug: event.slug,
            description: event.description ?? "",
            scoring_type: event.scoring_type,
            starts_at: event.starts_at,
            ends_at: event.ends_at,
          }}
        />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Challenges in this event ({challenges?.length ?? 0})</h3>
        {challenges && challenges.length > 0 ? (
          <ul className="divide-y divide-border">
            {challenges.map((c) => (
              <li key={c.id} className="flex items-center justify-between gap-4 py-2">
                <Link href={`/admin/ctf/${c.id}`} className="text-sm text-foreground hover:underline">
                  {c.title}
                </Link>
                <span className="text-xs text-foreground-subtle">{c.published ? "Published" : "Draft"}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-foreground-muted">
            No challenges assigned yet. Set this event from a challenge&rsquo;s own edit page.
          </p>
        )}
      </div>
    </div>
  );
}
