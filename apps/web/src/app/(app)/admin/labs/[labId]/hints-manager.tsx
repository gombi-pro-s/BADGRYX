"use client";

import { useActionState, useTransition } from "react";
import { createHintAction, deleteHintAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

interface Hint {
  id: string;
  level: number;
  content: string;
  point_cost: number;
}

export function HintsManager({ labId, hints }: { labId: string; hints: Hint[] }) {
  const action = createHintAction.bind(null, labId);
  const [state, formAction, pending] = useActionState(action, initialState);
  const [deletePending, startDelete] = useTransition();

  return (
    <div>
      {hints.length > 0 ? (
        <ul className="mb-4 space-y-2">
          {hints
            .slice()
            .sort((a, b) => a.level - b.level)
            .map((hint) => (
              <li key={hint.id} className="flex items-start justify-between gap-3 rounded-md border border-border p-3">
                <div className="min-w-0">
                  <p className="text-xs font-medium text-foreground-subtle">
                    Level {hint.level} &middot; {hint.point_cost} pts
                  </p>
                  <p className="mt-1 text-sm text-foreground">{hint.content}</p>
                </div>
                <button
                  type="button"
                  disabled={deletePending}
                  onClick={() => startDelete(() => deleteHintAction(labId, hint.id))}
                  className="shrink-0 text-xs text-danger hover:underline disabled:opacity-50"
                >
                  Remove
                </button>
              </li>
            ))}
        </ul>
      ) : (
        <p className="mb-4 text-sm text-foreground-muted">No hints yet.</p>
      )}

      <form action={formAction} className="space-y-3 rounded-md border border-dashed border-border p-3">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label htmlFor="level">Level (1-5)</Label>
            <Input id="level" name="level" type="number" min={1} max={5} required />
          </div>
          <div>
            <Label htmlFor="point_cost">Point cost</Label>
            <Input id="point_cost" name="point_cost" type="number" min={0} max={1000} defaultValue={0} required />
          </div>
        </div>
        <div>
          <Label htmlFor="content">Hint text</Label>
          <textarea
            id="content"
            name="content"
            required
            rows={2}
            maxLength={2000}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
        <FormError>{state.error}</FormError>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Adding..." : "Add hint"}
        </Button>
      </form>
    </div>
  );
}
