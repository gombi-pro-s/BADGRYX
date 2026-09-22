import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { SubmitReportForm } from "./submit-report-form";
import type { CapstoneStatus } from "@/types/database";

const STATUS_LABEL: Record<CapstoneStatus, string> = {
  submitted: "Submitted",
  under_review: "Under review",
  passed: "Passed",
  needs_revision: "Needs revision",
};
const STATUS_CLASS: Record<CapstoneStatus, string> = {
  submitted: "bg-background-subtle text-foreground-subtle",
  under_review: "bg-warning-muted text-warning",
  passed: "bg-success-muted text-success",
  needs_revision: "bg-danger-muted text-danger",
};

export default async function CapstoneDetailPage({ params }: { params: Promise<{ capstoneId: string }> }) {
  const { capstoneId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: capstone } = await supabase
    .from("capstones")
    .select("id, title, description, report_required")
    .eq("id", capstoneId)
    .eq("published", true)
    .maybeSingle();
  if (!capstone) notFound();

  const [{ data: skillLinks }, { data: labLinks }, { data: submissions }] = await Promise.all([
    supabase.from("capstone_skills").select("skill_id").eq("capstone_id", capstoneId),
    supabase.from("capstone_labs").select("lab_id").eq("capstone_id", capstoneId),
    supabase
      .from("capstone_submissions")
      .select("id, status, reviewer_notes, submitted_at, reviewed_at")
      .eq("capstone_id", capstoneId)
      .eq("user_id", user.id)
      .order("submitted_at", { ascending: false }),
  ]);

  const skillIds = (skillLinks ?? []).map((s) => s.skill_id);
  const labIds = (labLinks ?? []).map((l) => l.lab_id);
  const [{ data: skills }, { data: labs }] = await Promise.all([
    skillIds.length > 0 ? supabase.from("skills").select("id, name").in("id", skillIds) : Promise.resolve({ data: [] }),
    labIds.length > 0 ? supabase.from("labs").select("id, title").in("id", labIds) : Promise.resolve({ data: [] }),
  ]);

  const latestStatus = submissions?.[0]?.status;
  const alreadyPassed = latestStatus === "passed";

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/capstones" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; All capstones
      </Link>
      <h1 className="mb-4 text-2xl font-semibold text-foreground">{capstone.title}</h1>
      {capstone.description && (
        <p className="mb-6 whitespace-pre-wrap text-sm text-foreground-muted">{capstone.description}</p>
      )}

      {skills && skills.length > 0 && (
        <div className="mb-6">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-foreground-subtle">
            Skills demonstrated on a pass
          </h2>
          <div className="flex flex-wrap gap-2">
            {skills.map((s) => (
              <span key={s.id} className="rounded-full border border-border bg-surface px-3 py-1 text-xs text-foreground-muted">
                {s.name}
              </span>
            ))}
          </div>
        </div>
      )}

      {labs && labs.length > 0 && (
        <div className="mb-8">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-foreground-subtle">Related labs</h2>
          <div className="flex flex-wrap gap-2">
            {labs.map((l) => (
              <Link
                key={l.id}
                href={`/labs/${l.id}`}
                className="rounded-full border border-border bg-surface px-3 py-1 text-xs text-accent hover:underline"
              >
                {l.title}
              </Link>
            ))}
          </div>
        </div>
      )}

      {submissions && submissions.length > 0 && (
        <div className="mb-8">
          <h2 className="mb-2 text-sm font-semibold text-foreground">Your submissions</h2>
          <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
            {submissions.map((s) => (
              <li key={s.id} className="px-4 py-3">
                <div className="flex items-center justify-between gap-4">
                  <span className="text-xs text-foreground-subtle">
                    {new Date(s.submitted_at).toLocaleDateString()}
                  </span>
                  <span className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${STATUS_CLASS[s.status]}`}>
                    {STATUS_LABEL[s.status]}
                  </span>
                </div>
                {s.reviewer_notes && (
                  <p className="mt-2 text-xs text-foreground-muted">
                    <span className="font-medium text-foreground">Reviewer notes:</span> {s.reviewer_notes}
                  </p>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}

      {alreadyPassed ? (
        <div className="rounded-lg border border-success/30 bg-success-muted p-4 text-sm text-success">
          You&apos;ve already passed this capstone.
        </div>
      ) : (
        <div>
          <h2 className="mb-3 text-sm font-semibold text-foreground">
            {submissions && submissions.length > 0 ? "Submit again" : "Submit your report"}
          </h2>
          <SubmitReportForm capstoneId={capstone.id} />
        </div>
      )}
    </div>
  );
}
