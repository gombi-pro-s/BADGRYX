"use client";

import { useState, useTransition } from "react";

export function PublishToggle({
  published,
  onToggle,
}: {
  published: boolean;
  onToggle: (next: boolean) => Promise<void>;
}) {
  const [optimistic, setOptimistic] = useState(published);
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => {
        const next = !optimistic;
        setOptimistic(next);
        startTransition(async () => {
          try {
            await onToggle(next);
          } catch {
            setOptimistic(!next); // revert on failure
          }
        });
      }}
      className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium transition-opacity disabled:opacity-50 ${
        optimistic ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
      }`}
    >
      {optimistic ? "Published" : "Draft"}
    </button>
  );
}
