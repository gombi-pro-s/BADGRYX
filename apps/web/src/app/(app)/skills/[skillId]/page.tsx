import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { SkillStateBadge } from "@/components/skill-state-badge";
import type { SkillEvidenceOutcome, SkillState } from "@/types/database";

export const metadata: Metadata = { title: "Skill detail" };

const OUTCOME_LABEL: Record<SkillEvidenceOutcome, string> = { passed: "Passed", partial: "Partial", failed: "Failed" };
const OUTCOME_CLASS: Record<SkillEvidenceOutcome, string> = {
  passed: "text-success",
  partial: "text-warning",
  failed: "text-danger",
};

const EVIDENCE_TYPE_LABEL: Record<string, string> = {
  theory: "Theory",
  quiz: "Quiz",
  guided_lab: "Guided lab",
  unguided_lab: "Unguided lab",
  ctf: "CTF",
  assessment: "Assessment",
  remediation: "Remediation",
  retest: "Retest",
};

// Plain-language mirror of the state machine rules documented in
// 20260921000006_skill_graph.sql's recompute_skill_state() -- not invented
// copy, the exact same rule set the database enforces.
const STATE_EXPLANATION: Record<SkillState, string> = {
  NOT_STARTED: "No evidence yet for this skill. Start with a lesson, quiz, or lab that covers it.",
  LEARNING: "You've passed the theory check. Pass a guided lab or quiz to move to Practicing.",
  PRACTICING: "You've passed a guided lab or quiz. Pass a formal assessment to move to Assessed.",
  ASSESSED:
    "You've passed a formal assessment, but haven't yet demonstrated independent practical ability. Solve an unguided lab or CTF challenge to reach Demonstrated.",
  DEMONSTRATED:
    "You've independently solved an unguided lab or CTF challenge for this skill without guidance. Pass a formal assessment and a retest to reach Mastered.",
  MASTERED:
    "You've passed a formal assessment, independently demonstrated the skill, and it held up on retest -- the highest state this platform tracks.",
  NEEDS_REVIEW:
    "A recent assessment or retest for this skill failed after you'd previously reached Assessed or higher. Retest to recover your state.",
};

export default async function SkillDetailPage({ params }: { params: Promise<{ skillId: string }> }) {
  const { skillId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: skill } = await supabase
    .from("skills")
    .select("id, slug, name, category_id, description")
    .eq("id", skillId)
    .maybeSingle();
  if (!skill) notFound();

  const [{ data: category }, { data: prereqLinks }, { data: state }, { data: evidence }] = await Promise.all([
    supabase.from("skill_categories").select("name").eq("id", skill.category_id).maybeSingle(),
    supabase.from("skill_prerequisites").select("prerequisite_skill_id").eq("skill_id", skillId),
    supabase.from("user_skill_states").select("state").eq("user_id", user.id).eq("skill_id", skillId).maybeSingle(),
    supabase
      .from("skill_evidence")
      .select("id, evidence_type, outcome, source_type, score, hint_level_used, occurred_at")
      .eq("user_id", user.id)
      .eq("skill_id", skillId)
      .order("occurred_at", { ascending: false })
      .order("seq", { ascending: false }),
  ]);

  const prereqIds = (prereqLinks ?? []).map((p) => p.prerequisite_skill_id);
  const { data: prerequisites } =
    prereqIds.length > 0 ? await supabase.from("skills").select("id, name").in("id", prereqIds) : { data: [] };

  const currentState = (state?.state ?? "NOT_STARTED") as SkillState;

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <Link href="/skills" className="text-xs text-accent hover:underline">
        &larr; Skill Graph
      </Link>

      <div className="mt-2 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold text-foreground">{skill.name}</h1>
          <p className="mt-1 text-xs uppercase tracking-wide text-foreground-subtle">{category?.name}</p>
        </div>
        <SkillStateBadge state={currentState} />
      </div>

      {skill.description && <p className="mt-4 text-sm text-foreground-muted">{skill.description}</p>}

      <div className="mt-6 rounded-lg border border-border bg-surface p-4">
        <p className="text-sm text-foreground">{STATE_EXPLANATION[currentState]}</p>
      </div>

      {prerequisites && prerequisites.length > 0 && (
        <div className="mt-6">
          <h2 className="mb-2 text-sm font-semibold text-foreground">Prerequisites</h2>
          <ul className="flex flex-wrap gap-2">
            {prerequisites.map((p) => (
              <li key={p.id}>
                <Link
                  href={`/skills/${p.id}`}
                  className="rounded-full border border-border bg-surface px-3 py-1 text-xs text-foreground-muted hover:border-border-strong hover:text-foreground"
                >
                  {p.name}
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="mt-8">
        <h2 className="mb-3 text-sm font-semibold text-foreground">Evidence history</h2>
        {evidence && evidence.length > 0 ? (
          <div className="overflow-x-auto rounded-lg border border-border bg-surface">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-xs text-foreground-subtle">
                  <th className="px-4 py-2 font-medium">Type</th>
                  <th className="px-4 py-2 font-medium">Outcome</th>
                  <th className="px-4 py-2 font-medium">Source</th>
                  <th className="px-4 py-2 font-medium">Score</th>
                  <th className="px-4 py-2 font-medium">Hints</th>
                  <th className="px-4 py-2 font-medium">When</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {evidence.map((row) => (
                  <tr key={row.id}>
                    <td className="px-4 py-2.5 text-foreground">{EVIDENCE_TYPE_LABEL[row.evidence_type] ?? row.evidence_type}</td>
                    <td className={`px-4 py-2.5 font-medium ${OUTCOME_CLASS[row.outcome]}`}>
                      {OUTCOME_LABEL[row.outcome]}
                    </td>
                    <td className="px-4 py-2.5 text-foreground-muted">{row.source_type}</td>
                    <td className="px-4 py-2.5 text-foreground-muted">{row.score ?? "—"}</td>
                    <td className="px-4 py-2.5 text-foreground-muted">{row.hint_level_used ?? "—"}</td>
                    <td className="px-4 py-2.5 text-foreground-subtle">
                      {new Date(row.occurred_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="rounded-lg border border-dashed border-border bg-surface p-6 text-center text-sm text-foreground-muted">
            No evidence recorded for this skill yet.
          </div>
        )}
      </div>
    </div>
  );
}
