"use client";

import { useState, useTransition } from "react";
import { unenrollFactorAction } from "./actions";

export function RemoveFactorButton({ factorId }: { factorId: string }) {
  const [pending, startTransition] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!confirming) {
    return (
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className="shrink-0 text-xs font-medium text-danger hover:underline"
      >
        Remove
      </button>
    );
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex items-center gap-2">
        <span className="text-xs text-foreground-subtle">Remove this device?</span>
        <button
          type="button"
          disabled={pending}
          onClick={() =>
            startTransition(async () => {
              try {
                await unenrollFactorAction(factorId);
              } catch (err) {
                setError(err instanceof Error ? err.message : "Could not remove.");
                setConfirming(false);
              }
            })
          }
          className="text-xs font-medium text-danger hover:underline disabled:opacity-50"
        >
          {pending ? "..." : "Yes"}
        </button>
        <button
          type="button"
          onClick={() => setConfirming(false)}
          className="text-xs text-foreground-subtle hover:underline"
        >
          Cancel
        </button>
      </div>
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
}
