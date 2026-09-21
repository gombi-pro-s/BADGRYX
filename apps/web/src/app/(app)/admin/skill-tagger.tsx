"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";

interface Skill {
  id: string;
  name: string;
}

export function SkillTagger({
  allSkills,
  selectedSkillIds,
  onSave,
}: {
  allSkills: Skill[];
  selectedSkillIds: string[];
  onSave: (skillIds: string[]) => Promise<void>;
}) {
  const [selected, setSelected] = useState(new Set(selectedSkillIds));
  const [pending, startTransition] = useTransition();
  const [saved, setSaved] = useState(false);

  function toggle(skillId: string) {
    setSaved(false);
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(skillId)) next.delete(skillId);
      else next.add(skillId);
      return next;
    });
  }

  return (
    <div>
      <div className="mb-4 flex max-h-64 flex-wrap gap-2 overflow-y-auto">
        {allSkills.map((skill) => (
          <button
            key={skill.id}
            type="button"
            onClick={() => toggle(skill.id)}
            className={`rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
              selected.has(skill.id)
                ? "border-accent bg-accent-muted text-accent"
                : "border-border text-foreground-muted hover:border-border-strong"
            }`}
          >
            {skill.name}
          </button>
        ))}
      </div>
      <Button
        type="button"
        size="sm"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            await onSave([...selected]);
            setSaved(true);
          })
        }
      >
        {pending ? "Saving..." : "Save skills"}
      </Button>
      {saved && !pending && <span className="ml-3 text-xs text-success">Saved.</span>}
    </div>
  );
}
