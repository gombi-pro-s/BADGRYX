"use client";

import { useActionState, useState, useTransition } from "react";
import { deleteEnvironmentAction, saveEnvironmentAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

const PLACEHOLDER_SPEC = JSON.stringify(
  {
    hostname: "webserver01",
    initial_cwd: "/home/user",
    initial_user: "user",
    users: ["user", "root"],
    sudo_rules: [{ user: "user", allowed: ["cat"] }],
    filesystem: {
      "/home/user": { type: "dir", owner: "user", perms: "rwxr-xr-x" },
      "/home/user/notes.txt": { type: "file", owner: "user", perms: "rw-r--r--", content: "..." },
      "/root/flag.txt": { type: "file", owner: "root", perms: "rw-------", content: "ICOREPEN{...}" },
    },
  },
  null,
  2,
);

interface Environment {
  id: string;
  variant_seed: number;
  spec: unknown;
}

export function EnvironmentManager({ labId, environments }: { labId: string; environments: Environment[] }) {
  const action = saveEnvironmentAction.bind(null, labId);
  const [state, formAction, pending] = useActionState(action, initialState);
  const [deletePending, startDelete] = useTransition();
  const [specJson, setSpecJson] = useState(PLACEHOLDER_SPEC);

  return (
    <div>
      <p className="mb-3 text-xs text-foreground-subtle">
        The spec is never sent to a learner&apos;s browser directly (see ADR 0009) -- only the output of a
        command they run against it. Saving here validates against the exact schema the terminal execution
        engine parses, so a spec that saves is one that will actually work.
      </p>

      {environments.length > 0 ? (
        <ul className="mb-4 space-y-2">
          {environments.map((env) => (
            <li key={env.id} className="flex items-center justify-between gap-3 rounded-md border border-border p-3">
              <span className="text-sm text-foreground">Variant {env.variant_seed}</span>
              <div className="flex items-center gap-3">
                <button
                  type="button"
                  onClick={() => setSpecJson(JSON.stringify(env.spec, null, 2))}
                  className="text-xs font-medium text-accent hover:underline"
                >
                  Load into editor
                </button>
                <button
                  type="button"
                  disabled={deletePending}
                  onClick={() => startDelete(() => deleteEnvironmentAction(labId, env.id))}
                  className="text-xs text-danger hover:underline disabled:opacity-50"
                >
                  Remove
                </button>
              </div>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mb-4 text-sm text-foreground-muted">
          No terminal environment yet -- this lab has no interactive terminal until one is saved.
        </p>
      )}

      <form action={formAction} className="space-y-3 rounded-md border border-dashed border-border p-3">
        <div className="w-32">
          <Label htmlFor="variant_seed">Variant seed</Label>
          <input
            id="variant_seed"
            name="variant_seed"
            type="number"
            min={0}
            max={9999}
            defaultValue={0}
            required
            className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
        <div>
          <Label htmlFor="spec_json">Environment spec (JSON)</Label>
          <textarea
            id="spec_json"
            name="spec_json"
            value={specJson}
            onChange={(e) => setSpecJson(e.target.value)}
            rows={16}
            required
            spellCheck={false}
            className="w-full resize-y rounded-md border border-border bg-surface px-3 py-2 font-mono text-xs text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
        <FormError>{state.error}</FormError>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Saving..." : "Save environment"}
        </Button>
      </form>
    </div>
  );
}
