import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateAnnouncementForm } from "./create-announcement-form";

export const metadata: Metadata = { title: "Announcements" };

export default async function AdminAnnouncementsPage() {
  const supabase = await createClient();
  const { data: announcements } = await supabase
    .from("announcements")
    .select("id, title, published, published_at, expires_at, created_at")
    .is("organization_id", null)
    .order("created_at", { ascending: false });

  const now = new Date().getTime();

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">Platform Announcements</h2>
      <p className="mb-4 text-sm text-foreground-muted">
        Shown on every learner&rsquo;s dashboard while published and not expired. Org-scoped
        announcements are authored by instructors from their own organization page instead.
      </p>

      {announcements && announcements.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {announcements.map((a) => {
            const expired = a.expires_at ? new Date(a.expires_at).getTime() < now : false;
            return (
              <li key={a.id} className="flex items-center justify-between gap-4 px-4 py-3">
                <Link
                  href={`/admin/announcements/${a.id}`}
                  className="min-w-0 text-sm font-medium text-foreground hover:underline"
                >
                  {a.title}
                </Link>
                <span
                  className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                    expired
                      ? "bg-background-subtle text-foreground-subtle"
                      : a.published
                        ? "bg-success-muted text-success"
                        : "bg-background-subtle text-foreground-subtle"
                  }`}
                >
                  {expired ? "Expired" : a.published ? "Published" : "Draft"}
                </span>
              </li>
            );
          })}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No platform announcements yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New announcement</h3>
        <CreateAnnouncementForm />
      </div>
    </div>
  );
}
