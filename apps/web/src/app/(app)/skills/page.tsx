import type { Metadata } from "next";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { SkillStateBadge } from "@/components/skill-state-badge";
import type { SkillState } from "@/types/database";

export const metadata: Metadata = { title: "Skill Graph" };

export default async function SkillsPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: categories }, { data: skills }, { data: states }] = await Promise.all([
    supabase.from("skill_categories").select("id, slug, name, sort_order").order("sort_order"),
    supabase.from("skills").select("id, slug, name, category_id, description").order("name"),
    supabase.from("user_skill_states").select("skill_id, state").eq("user_id", user.id),
  ]);

  const stateBySkillId = new Map((states ?? []).map((s) => [s.skill_id, s.state as SkillState]));
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
    <div className="mx-auto max-w-5xl px-6 py-10">
      <header className="mb-8">
        <h1 className="text-2xl font-semibold text-foreground">Skill Graph</h1>
        <p className="mt-1 text-sm text-foreground-muted">
          Course completion isn&apos;t mastery. Every state below is backed by evidence: a passed
          quiz, a completed lab, a solved challenge, an assessment, a retest.
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
                <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
                  {categorySkills.map((skill) => (
                    <li key={skill.id} className="flex items-center justify-between gap-4 px-4 py-3">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium text-foreground">{skill.name}</p>
                        {skill.description && (
                          <p className="mt-0.5 truncate text-xs text-foreground-subtle">
                            {skill.description}
                          </p>
                        )}
                      </div>
                      <SkillStateBadge state={stateBySkillId.get(skill.id) ?? "NOT_STARTED"} />
                    </li>
                  ))}
                </ul>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}
