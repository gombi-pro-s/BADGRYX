import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { EditReportForm } from "../edit-report-form";
import { DeleteReportButton } from "../delete-report-button";

export default async function ReportDetailPage({ params }: { params: Promise<{ reportId: string }> }) {
  const { reportId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: report } = await supabase
    .from("reports")
    .select("id, title, kind, content_markdown")
    .eq("id", reportId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!report) notFound();

  const mentorMode = report.kind === "methodology" ? "review_methodology" : "review_report";

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <Link href="/reports" className="mb-4 inline-block text-sm text-foreground-muted hover:underline">
        &larr; Back to reports
      </Link>

      <div className="mb-6 flex items-center justify-between gap-4">
        <h1 className="text-lg font-semibold text-foreground">{report.title}</h1>
        <div className="flex shrink-0 items-center gap-4">
          <Link
            href={`/mentor?contextType=report&contextId=${report.id}&mode=${mentorMode}`}
            className="text-sm font-medium text-accent hover:underline"
          >
            Ask Mentor to review
          </Link>
          <DeleteReportButton reportId={report.id} />
        </div>
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <EditReportForm
          reportId={report.id}
          initial={{ title: report.title, kind: report.kind, content_markdown: report.content_markdown }}
        />
      </div>
    </div>
  );
}
