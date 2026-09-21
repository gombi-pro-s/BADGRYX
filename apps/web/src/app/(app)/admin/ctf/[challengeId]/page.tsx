import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { SkillTagger } from "../../skill-tagger";
import { setChallengeSkillsAction, toggleChallengePublishedAction } from "../actions";
import { EditChallengeForm } from "./edit-challenge-form";

export default async function AdminChallengeDetailPage({
  params,
}: {
  params: Promise<{ challengeId: string }>;
}) {
  const { challengeId } = await params;
  const supabase = await createClient();

  const [{ data: challenge }, { data: allSkills }, { data: challengeSkills }] = await Promise.all([
    supabase
      .from("ctf_challenges")
      .select("id, slug, title, description, category, difficulty, points, published")
      .eq("id", challengeId)
      .single(),
    supabase.from("skills").select("id, name").order("name"),
    supabase.from("ctf_challenge_skills").select("skill_id").eq("challenge_id", challengeId),
  ]);

  if (!challenge) notFound();

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{challenge.title}</h2>
        <PublishToggle
          published={challenge.published}
          onToggle={toggleChallengePublishedAction.bind(null, challenge.id)}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Challenge details</h3>
        <EditChallengeForm
          challengeId={challenge.id}
          initial={{
            slug: challenge.slug,
            title: challenge.title,
            description: challenge.description ?? "",
            category: challenge.category,
            difficulty: challenge.difficulty,
            points: challenge.points,
          }}
        />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Skills demonstrated</h3>
        <SkillTagger
          allSkills={allSkills ?? []}
          selectedSkillIds={(challengeSkills ?? []).map((s) => s.skill_id)}
          onSave={(skillIds) => setChallengeSkillsAction(challenge.id, skillIds)}
        />
      </div>
    </div>
  );
}
