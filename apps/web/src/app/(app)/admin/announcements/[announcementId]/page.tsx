import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { toggleAnnouncementPublishedAction } from "../actions";
import { EditAnnouncementForm } from "../edit-announcement-form";
import { DeleteAnnouncementButton } from "../delete-announcement-button";

export default async function AdminAnnouncementDetailPage({
  params,
}: {
  params: Promise<{ announcementId: string }>;
}) {
  const { announcementId } = await params;
  const supabase = await createClient();

  const { data: announcement } = await supabase
    .from("announcements")
    .select("id, title, body_markdown, published, expires_at")
    .eq("id", announcementId)
    .is("organization_id", null)
    .maybeSingle();

  if (!announcement) notFound();

  const { data: translation } = await supabase
    .from("announcement_translations")
    .select("title, body_markdown")
    .eq("announcement_id", announcementId)
    .eq("locale", "es")
    .maybeSingle();

  return (
    <div>
      <Link href="/admin/announcements" className="mb-4 inline-block text-sm text-foreground-muted hover:underline">
        &larr; Back to announcements
      </Link>

      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{announcement.title}</h2>
        <div className="flex items-center gap-4">
          <PublishToggle
            published={announcement.published}
            onToggle={toggleAnnouncementPublishedAction.bind(null, announcement.id)}
          />
          <DeleteAnnouncementButton announcementId={announcement.id} />
        </div>
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <EditAnnouncementForm
          announcementId={announcement.id}
          initial={{
            title: announcement.title,
            body_markdown: announcement.body_markdown,
            expires_at: announcement.expires_at,
            title_es: translation?.title ?? null,
            body_markdown_es: translation?.body_markdown ?? null,
          }}
        />
      </div>
    </div>
  );
}
