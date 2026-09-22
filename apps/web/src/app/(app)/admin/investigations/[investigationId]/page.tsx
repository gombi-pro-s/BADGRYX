import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { SkillTagger } from "../../skill-tagger";
import { setInvestigationSkillsAction, toggleInvestigationPublishedAction } from "../actions";
import { EditInvestigationForm } from "./edit-investigation-form";
import { ArtifactsManager } from "./artifacts-manager";
import { QuestionsManager } from "./questions-manager";

export default async function AdminInvestigationDetailPage({
  params,
}: {
  params: Promise<{ investigationId: string }>;
}) {
  const { investigationId } = await params;
  const supabase = await createClient();

  const [
    { data: investigation },
    { data: allSkills },
    { data: investigationSkills },
    { data: artifacts },
    { data: questions },
    { data: choices },
  ] = await Promise.all([
    supabase
      .from("investigations")
      .select("id, slug, title, briefing, category, difficulty, estimated_minutes, points, passing_score, published")
      .eq("id", investigationId)
      .single(),
    supabase.from("skills").select("id, name").order("name"),
    supabase.from("investigation_skills").select("skill_id").eq("investigation_id", investigationId),
    supabase
      .from("investigation_artifacts")
      .select("id, artifact_type, title, content")
      .eq("investigation_id", investigationId)
      .order("order_index"),
    supabase
      .from("investigation_questions")
      .select("id, question_text, question_type, points")
      .eq("investigation_id", investigationId)
      .order("order_index"),
    supabase.from("investigation_choices").select("id, question_id, choice_text, is_correct").order("order_index"),
  ]);

  if (!investigation) notFound();

  const questionsWithChoices = (questions ?? []).map((q) => ({
    ...q,
    choices: (choices ?? []).filter((c) => c.question_id === q.id),
  }));

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{investigation.title}</h2>
        <PublishToggle
          published={investigation.published}
          onToggle={toggleInvestigationPublishedAction.bind(null, investigation.id)}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Investigation details</h3>
        <EditInvestigationForm
          investigationId={investigation.id}
          initial={{
            slug: investigation.slug,
            title: investigation.title,
            briefing: investigation.briefing ?? "",
            category: investigation.category,
            difficulty: investigation.difficulty,
            estimated_minutes: investigation.estimated_minutes,
            points: investigation.points,
            passing_score: investigation.passing_score,
          }}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Skills demonstrated</h3>
        <SkillTagger
          allSkills={allSkills ?? []}
          selectedSkillIds={(investigationSkills ?? []).map((s) => s.skill_id)}
          onSave={(skillIds) => setInvestigationSkillsAction(investigation.id, skillIds)}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Evidence artifacts</h3>
        <ArtifactsManager investigationId={investigation.id} artifacts={artifacts ?? []} />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Questions</h3>
        <QuestionsManager investigationId={investigation.id} questions={questionsWithChoices} />
      </div>
    </div>
  );
}
