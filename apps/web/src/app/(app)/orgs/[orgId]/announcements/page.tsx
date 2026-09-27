import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireOrgInstructor } from "@/lib/auth/org";
import { createClient } from "@/lib/supabase/server";
import { CreateOrgAnnouncementForm } from "./create-announcement-form";

export const metadata: Metadata = { title: "Announcements" };

export default async function OrgAnnouncementsPage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  await requireOrgInstructor(orgId);
  const supabase = await createClient();

  const { data: organization } = await supabase.from("organizations").select("id, name").eq("id", orgId).maybeSingle();
  if (!organization) notFound();

  const { data: announcements } = await supabase
    .from("announcements")
    .select("id, title, published, published_at, expires_at, created_at")
    .eq("organization_id", orgId)
    .order("created_at", { ascending: false });

  const now = new Date().getTime();

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <Link href={`/orgs/${orgId}`} className="mb-4 inline-block text-sm text-foreground-muted hover:underline">
        &larr; Back to {organization.name}
      </Link>
      <h1 className="mb-1 text-lg font-semibold text-foreground">Announcements</h1>
      <p className="mb-6 text-sm text-foreground-muted">
        Shown on the dashboard of every member of {organization.name} while published and not expired.
      </p>

      {announcements && announcements.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {announcements.map((a) => {
            const expired = a.expires_at ? new Date(a.expires_at).getTime() < now : false;
            return (
              <li key={a.id} className="flex items-center justify-between gap-4 px-4 py-3">
                <Link
                  href={`/orgs/${orgId}/announcements/${a.id}`}
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
          No announcements yet. Post the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h2 className="mb-4 text-sm font-semibold text-foreground">New announcement</h2>
        <CreateOrgAnnouncementForm organizationId={orgId} />
      </div>
    </div>
  );
}
