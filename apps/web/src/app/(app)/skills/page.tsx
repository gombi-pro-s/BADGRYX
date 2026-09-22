import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { SkillStateBadge } from "@/components/skill-state-badge";
import { EvidenceCell } from "@/components/evidence-cell";
import type { SkillEvidenceOutcome, SkillEvidenceType, SkillState } from "@/types/database";

export const metadata: Metadata = { title: "Skill Graph" };

const EVIDENCE_COLUMNS: { type: SkillEvidenceType; label: string; short: string }[] = [
  { type: "theory", label: "Theory", short: "Thy" },
  { type: "quiz", label: "Quiz", short: "Quiz" },
  { type: "guided_lab", label: "Guided lab", short: "Gdd" },
  { type: "unguided_lab", label: "Unguided lab", short: "Ung" },
  { type: "ctf", label: "CTF", short: "CTF" },
  { type: "assessment", label: "Assessment", short: "Asmt" },
  { type: "remediation", label: "Remediation", short: "Rmd" },
  { type: "retest", label: "Retest", short: "Rtst" },
];

// Passed beats partial beats failed -- matches the state machine's own
// `bool_or(... = 'passed')` logic: what matters is whether this type of
// evidence was EVER passed for this skill, not the most recent attempt.
const OUTCOME_PRIORITY: Record<SkillEvidenceOutcome, number> = { passed: 2, partial: 1, failed: 0 };

export default async function SkillsPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: categories }, { data: skills }, { data: states }, { data: evidence }] = await Promise.all([
    supabase.from("skill_categories").select("id, slug, name, sort_order").order("sort_order"),
    supabase.from("skills").select("id, slug, name, category_id, description").order("name"),
    supabase.from("user_skill_states").select("skill_id, state").eq("user_id", user.id),
    supabase.from("skill_evidence").select("skill_id, evidence_type, outcome").eq("user_id", user.id),
  ]);

  const stateBySkillId = new Map((states ?? []).map((s) => [s.skill_id, s.state as SkillState]));

  const outcomeByCell = new Map<string, SkillEvidenceOutcome>();
  for (const row of evidence ?? []) {
    const key = `${row.skill_id}:${row.evidence_type}`;
    const existing = outcomeByCell.get(key);
    if (!existing || OUTCOME_PRIORITY[row.outcome] > OUTCOME_PRIORITY[existing]) {
      outcomeByCell.set(key, row.outcome);
    }
  }

  const skillsByCategory = new Map<string, typeof skills>();
  for (const skill of skills ?? []) {
    const list = skillsByCategory.get(skill.category_id) ?? [];
    list.push(skill);
    skillsByCategory.set(skill.category_id, list);
  }

  const totalSkills = skills?.length ?? 0;
  const masteredCount = [...stateBySkillId.values()].filter((s) => s === "MASTERED").length;
  const needsReviewCount = [...stateBySkillId.values()].filter((s) => s === "NEEDS_REVIEW").length;

  return (
    <div className="mx-auto max-w-6xl px-6 py-10">
      <header className="mb-8">
        <h1 className="text-2xl font-semibold text-foreground">Skill Graph</h1>
        <p className="mt-1 text-sm text-foreground-muted">
          Course completion isn&apos;t mastery. Every column below is real evidence -- a passed quiz, a
          completed lab, a solved challenge, an assessment, a retest -- not a self-reported checklist. Click a
          skill for its full evidence history.
        </p>
        <dl className="mt-6 grid grid-cols-3 gap-4 sm:max-w-md">
          <div className="rounded-lg border border-border bg-surface p-4">
            <dt className="text-xs text-foreground-subtle">Skills tracked</dt>
            <dd className="mt-1 text-xl font-semibold text-foreground">{totalSkills}</dd>
          </div>
          <div className="rounded-lg border border-border bg-surface p-4">
            <dt className="text-xs text-foreground-subtle">Mastered</dt>
            <dd className="mt-1 text-xl font-semibold text-success">{masteredCount}</dd>
          </div>
          <div className="rounded-lg border border-border bg-surface p-4">
            <dt className="text-xs text-foreground-subtle">Needs review</dt>
            <dd className="mt-1 text-xl font-semibold text-danger">{needsReviewCount}</dd>
          </div>
        </dl>
      </header>

      {!categories?.length ? (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No skill catalog has been loaded yet.
        </div>
      ) : (
        <div className="space-y-8">
          {categories.map((category) => {
            const categorySkills = skillsByCategory.get(category.id) ?? [];
            if (categorySkills.length === 0) return null;
            return (
              <section key={category.id}>
                <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-foreground-subtle">
                  {category.name}
                </h2>
                <div className="overflow-x-auto rounded-lg border border-border bg-surface">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border text-left text-xs text-foreground-subtle">
                        <th className="px-4 py-2 font-medium">Skill</th>
                        {EVIDENCE_COLUMNS.map((col) => (
                          <th key={col.type} title={col.label} className="px-1.5 py-2 text-center font-medium">
                            {col.short}
                          </th>
                        ))}
                        <th className="px-4 py-2 font-medium">State</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {categorySkills.map((skill) => (
                        <tr key={skill.id} className="hover:bg-background-subtle">
                          <td className="px-4 py-2.5">
                            <Link href={`/skills/${skill.id}`} className="font-medium text-foreground hover:underline">
                              {skill.name}
                            </Link>
                          </td>
                          {EVIDENCE_COLUMNS.map((col) => (
                            <td key={col.type} className="px-1.5 py-2.5 text-center">
                              <EvidenceCell
                                outcome={outcomeByCell.get(`${skill.id}:${col.type}`) ?? null}
                                label={col.label}
                              />
                            </td>
                          ))}
                          <td className="px-4 py-2.5">
                            <SkillStateBadge state={stateBySkillId.get(skill.id) ?? "NOT_STARTED"} />
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}
