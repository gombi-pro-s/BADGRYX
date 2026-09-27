"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";

interface TaggableItem {
  id: string;
  title: string;
}

/** A generic version of the capstones admin's LabTagger/SkillTagger pattern -- toggle-chip multi-select with an explicit save. Used for both related labs and related CTF challenges on an investigation, so the save-button label is a prop rather than hardcoded. */
export function ItemTagger({
  allItems,
  selectedIds,
  onSave,
  saveLabel,
  emptyLabel,
}: {
  allItems: TaggableItem[];
  selectedIds: string[];
  onSave: (ids: string[]) => Promise<void>;
  saveLabel: string;
  emptyLabel: string;
}) {
  const [selected, setSelected] = useState(new Set(selectedIds));
  const [pending, startTransition] = useTransition();
  const [saved, setSaved] = useState(false);

  function toggle(id: string) {
    setSaved(false);
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  if (allItems.length === 0) {
    return <p className="text-sm text-foreground-muted">{emptyLabel}</p>;
  }

  return (
    <div>
      <div className="mb-4 flex max-h-64 flex-wrap gap-2 overflow-y-auto">
        {allItems.map((item) => (
          <button
            key={item.id}
            type="button"
            onClick={() => toggle(item.id)}
            className={`rounded-full border px-3 py-1 text-xs font-medium transition-colors ${
              selected.has(item.id)
                ? "border-accent bg-accent-muted text-accent"
                : "border-border text-foreground-muted hover:border-border-strong"
            }`}
          >
            {item.title}
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
        {pending ? "Saving..." : saveLabel}
      </Button>
      {saved && !pending && <span className="ml-3 text-xs text-success">Saved.</span>}
    </div>
  );
}
