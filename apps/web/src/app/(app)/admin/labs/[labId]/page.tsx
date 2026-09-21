import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { SkillTagger } from "../../skill-tagger";
import { setLabSkillsAction, toggleLabPublishedAction } from "../actions";
import { EditLabForm } from "./edit-lab-form";
import { HintsManager } from "./hints-manager";
import { FlagsManager } from "./flags-manager";

export default async function AdminLabDetailPage({
  params,
}: {
  params: Promise<{ labId: string }>;
}) {
  const { labId } = await params;
  const supabase = await createClient();

  const [{ data: lab }, { data: allSkills }, { data: labSkills }, { data: hints }, { data: flags }] =
    await Promise.all([
      supabase
        .from("labs")
        .select("id, slug, title, description, category, difficulty, estimated_minutes, points, published")
        .eq("id", labId)
        .single(),
      supabase.from("skills").select("id, name").order("name"),
      supabase.from("lab_skills").select("skill_id").eq("lab_id", labId),
      supabase.from("lab_hints").select("id, level, content, point_cost").eq("lab_id", labId),
      supabase.from("lab_flags").select("id, label, variant_seed").eq("lab_id", labId),
    ]);

  if (!lab) notFound();

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{lab.title}</h2>
        <PublishToggle published={lab.published} onToggle={toggleLabPublishedAction.bind(null, lab.id)} />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Lab details</h3>
        <EditLabForm
          labId={lab.id}
          initial={{
            slug: lab.slug,
            title: lab.title,
            description: lab.description ?? "",
            category: lab.category,
            difficulty: lab.difficulty,
            estimated_minutes: lab.estimated_minutes,
            points: lab.points,
          }}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Skills demonstrated</h3>
        <SkillTagger
          allSkills={allSkills ?? []}
          selectedSkillIds={(labSkills ?? []).map((s) => s.skill_id)}
          onSave={(skillIds) => setLabSkillsAction(lab.id, skillIds)}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Hints</h3>
        <HintsManager labId={lab.id} hints={hints ?? []} />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Flags</h3>
        <FlagsManager labId={lab.id} flags={flags ?? []} />
      </div>
    </div>
  );
}
