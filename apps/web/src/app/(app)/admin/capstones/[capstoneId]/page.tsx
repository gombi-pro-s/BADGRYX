import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { SkillTagger } from "../../skill-tagger";
import { setCapstoneSkillsAction, setCapstoneLabsAction, toggleCapstonePublishedAction } from "../actions";
import { EditCapstoneForm } from "./edit-capstone-form";
import { LabTagger } from "./lab-tagger";
import { ReviewSubmissionForm } from "./review-submission-form";

const STATUS_LABEL: Record<string, string> = {
  submitted: "Submitted",
  under_review: "Under review",
  passed: "Passed",
  needs_revision: "Needs revision",
};
const STATUS_CLASS: Record<string, string> = {
  submitted: "bg-background-subtle text-foreground-subtle",
  under_review: "bg-warning-muted text-warning",
  passed: "bg-success-muted text-success",
  needs_revision: "bg-danger-muted text-danger",
};

export default async function AdminCapstoneDetailPage({ params }: { params: Promise<{ capstoneId: string }> }) {
  const { capstoneId } = await params;
  const supabase = await createClient();

  const [
    { data: capstone },
    { data: allSkills },
    { data: capstoneSkills },
    { data: allLabs },
    { data: capstoneLabs },
    { data: submissions },
  ] = await Promise.all([
    supabase.from("capstones").select("id, slug, title, description, report_required, published").eq("id", capstoneId).single(),
    supabase.from("skills").select("id, name").order("name"),
    supabase.from("capstone_skills").select("skill_id").eq("capstone_id", capstoneId),
    supabase.from("labs").select("id, title").order("title"),
    supabase.from("capstone_labs").select("lab_id").eq("capstone_id", capstoneId),
    supabase
      .from("capstone_submissions")
      .select("id, user_id, report_content, status, reviewer_notes, submitted_at, reviewed_at")
      .eq("capstone_id", capstoneId)
      .order("submitted_at", { ascending: false }),
  ]);

  if (!capstone) notFound();

  const submitterIds = [...new Set((submissions ?? []).map((s) => s.user_id))];
  const { data: profiles } =
    submitterIds.length > 0
      ? await supabase.from("profiles").select("id, display_name, username").in("id", submitterIds)
      : { data: [] };
  const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{capstone.title}</h2>
        <PublishToggle published={capstone.published} onToggle={toggleCapstonePublishedAction.bind(null, capstone.id)} />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Capstone details</h3>
        <EditCapstoneForm
          capstoneId={capstone.id}
          initial={{
            slug: capstone.slug,
            title: capstone.title,
            description: capstone.description ?? "",
            report_required: capstone.report_required,
          }}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Skills demonstrated on a pass</h3>
        <SkillTagger
          allSkills={allSkills ?? []}
          selectedSkillIds={(capstoneSkills ?? []).map((s) => s.skill_id)}
          onSave={(skillIds) => setCapstoneSkillsAction(capstone.id, skillIds)}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Related labs</h3>
        <LabTagger
          allLabs={allLabs ?? []}
          selectedLabIds={(capstoneLabs ?? []).map((l) => l.lab_id)}
          onSave={(labIds) => setCapstoneLabsAction(capstone.id, labIds)}
        />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Submissions ({submissions?.length ?? 0})</h3>
        {submissions && submissions.length > 0 ? (
          <ul className="space-y-4">
            {submissions.map((s) => {
              const profile = profileById.get(s.user_id);
              return (
                <li key={s.id} className="rounded-md border border-border p-4">
                  <div className="mb-2 flex items-center justify-between gap-4">
                    <span className="text-sm font-medium text-foreground">
                      {profile?.display_name ?? profile?.username ?? s.user_id}
                    </span>
                    <span className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${STATUS_CLASS[s.status]}`}>
                      {STATUS_LABEL[s.status]}
                    </span>
                  </div>
                  {s.report_content && (
                    <p className="mb-3 whitespace-pre-wrap text-xs text-foreground-muted">{s.report_content}</p>
                  )}
                  {s.reviewer_notes && (
                    <p className="mb-3 rounded-md bg-background-subtle p-2 text-xs text-foreground-muted">
                      <span className="font-medium text-foreground">Reviewer notes:</span> {s.reviewer_notes}
                    </p>
                  )}
                  <ReviewSubmissionForm submissionId={s.id} currentStatus={s.status} />
                </li>
              );
            })}
          </ul>
        ) : (
          <p className="text-sm text-foreground-muted">No submissions yet.</p>
        )}
      </div>
    </div>
  );
}
