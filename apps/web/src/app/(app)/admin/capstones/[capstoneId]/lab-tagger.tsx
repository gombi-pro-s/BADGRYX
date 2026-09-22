"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";

interface Lab {
  id: string;
  title: string;
}

export function LabTagger({
  allLabs,
  selectedLabIds,
  onSave,
}: {
  allLabs: Lab[];
  selectedLabIds: string[];
  onSave: (labIds: string[]) => Promise<void>;
}) {
  const [selected, setSelected] = useState(new Set(selectedLabIds));
  const [pending, startTransition] = useTransition();
  const [saved, setSaved] = useState(false);

  function toggle(labId: string) {
    setSaved(false);
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(labId)) next.delete(labId);
      else next.add(labId);
      return next;
    });
  }

  return (
    <div>
      <div className="mb-4 flex max-h-64 flex-wrap gap-2 overflow-y-auto">
        {allLabs.map((lab) => (
          <button
            key={lab.id}
            type="button"
            onClick={() => toggle(lab.id)}
            className={`rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
              selected.has(lab.id)
                ? "border-accent bg-accent-muted text-accent"
                : "border-border text-foreground-muted hover:border-border-strong"
            }`}
          >
            {lab.title}
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
        {pending ? "Saving..." : "Save labs"}
      </Button>
      {saved && !pending && <span className="ml-3 text-xs text-success">Saved.</span>}
    </div>
  );
}
