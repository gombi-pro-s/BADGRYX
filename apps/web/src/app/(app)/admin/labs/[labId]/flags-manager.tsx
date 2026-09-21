"use client";

import { useActionState, useTransition } from "react";
import { createFlagAction, deleteFlagAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

interface Flag {
  id: string;
  label: string;
  variant_seed: number;
}

export function FlagsManager({ labId, flags }: { labId: string; flags: Flag[] }) {
  const action = createFlagAction.bind(null, labId);
  const [state, formAction, pending] = useActionState(action, initialState);
  const [deletePending, startDelete] = useTransition();

  return (
    <div>
      <p className="mb-3 text-xs text-foreground-subtle">
        Flags are hashed (SHA-256) the moment you submit this form. The plaintext is never stored,
        logged, or shown again after creation — write it down before submitting.
      </p>
      {flags.length > 0 ? (
        <ul className="mb-4 space-y-2">
          {flags.map((flag) => (
            <li key={flag.id} className="flex items-center justify-between gap-3 rounded-md border border-border p-3">
              <span className="text-sm text-foreground">
                {flag.label} <span className="text-foreground-subtle">(variant {flag.variant_seed})</span>
              </span>
              <button
                type="button"
                disabled={deletePending}
                onClick={() => startDelete(() => deleteFlagAction(labId, flag.id))}
                className="shrink-0 text-xs text-danger hover:underline disabled:opacity-50"
              >
                Remove
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mb-4 text-sm text-foreground-muted">No flags yet. The lab cannot be completed without one.</p>
      )}

      <form action={formAction} className="space-y-3 rounded-md border border-dashed border-border p-3">
        <div className="grid grid-cols-2 gap-3">
          <div>
            <Label htmlFor="label">Label</Label>
            <Input id="label" name="label" defaultValue="flag" required maxLength={100} />
          </div>
          <div>
            <Label htmlFor="variant_seed">Variant seed</Label>
            <Input id="variant_seed" name="variant_seed" type="number" min={0} max={9999} defaultValue={0} required />
          </div>
        </div>
        <div>
          <Label htmlFor="plaintext">Flag (plaintext, hashed on submit)</Label>
          <Input id="plaintext" name="plaintext" required minLength={4} maxLength={500} autoComplete="off" />
        </div>
        <FormError>{state.error}</FormError>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Adding..." : "Add flag"}
        </Button>
      </form>
    </div>
  );
}
