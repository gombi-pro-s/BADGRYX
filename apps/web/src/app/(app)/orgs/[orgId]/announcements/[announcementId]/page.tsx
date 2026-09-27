import Link from "next/link";
import { notFound } from "next/navigation";
import { requireOrgInstructor } from "@/lib/auth/org";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "@/app/(app)/admin/publish-toggle";
import { toggleOrgAnnouncementPublishedAction } from "../actions";
import { EditOrgAnnouncementForm } from "../edit-announcement-form";
import { DeleteOrgAnnouncementButton } from "../delete-announcement-button";

export default async function OrgAnnouncementDetailPage({
  params,
}: {
  params: Promise<{ orgId: string; announcementId: string }>;
}) {
  const { orgId, announcementId } = await params;
  await requireOrgInstructor(orgId);
  const supabase = await createClient();

  const { data: announcement } = await supabase
    .from("announcements")
    .select("id, title, body_markdown, published, expires_at")
    .eq("id", announcementId)
    .eq("organization_id", orgId)
    .maybeSingle();

  if (!announcement) notFound();

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <Link href={`/orgs/${orgId}/announcements`} className="mb-4 inline-block text-sm text-foreground-muted hover:underline">
        &larr; Back to announcements
      </Link>

      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-lg font-semibold text-foreground">{announcement.title}</h1>
        <div className="flex items-center gap-4">
          <PublishToggle
            published={announcement.published}
            onToggle={toggleOrgAnnouncementPublishedAction.bind(null, orgId, announcement.id)}
          />
          <DeleteOrgAnnouncementButton organizationId={orgId} announcementId={announcement.id} />
        </div>
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <EditOrgAnnouncementForm
          organizationId={orgId}
          announcementId={announcement.id}
          initial={{
            title: announcement.title,
            body_markdown: announcement.body_markdown,
            expires_at: announcement.expires_at,
          }}
        />
      </div>
    </div>
  );
}
