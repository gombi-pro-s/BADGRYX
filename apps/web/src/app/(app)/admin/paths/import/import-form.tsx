"use client";

import Link from "next/link";
import { useActionState, useRef } from "react";
import { importPathBundleAction, initialImportState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Label } from "@/components/ui/input";

export function ImportPathForm() {
  const [state, formAction, pending] = useActionState(importPathBundleAction, initialImportState);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      if (textareaRef.current && typeof reader.result === "string") {
        textareaRef.current.value = reader.result;
      }
    };
    reader.readAsText(file);
  }

  if (state.importedPathId) {
    return (
      <div className="rounded-lg border border-success/30 bg-success-muted p-6 text-sm text-success">
        <p className="font-medium">Imported &ldquo;{state.importedSlug}&rdquo; successfully.</p>
        {state.warnings.length > 0 && (
          <ul className="mt-3 list-inside list-disc space-y-1 text-foreground-muted">
            {state.warnings.map((w) => (
              <li key={w}>{w}</li>
            ))}
          </ul>
        )}
        <div className="mt-4 flex gap-3">
          <Link href={`/admin/paths/${state.importedPathId}`} className="font-medium underline">
            Review the imported path
          </Link>
          <Link href="/admin/paths/import" className="font-medium underline">
            Import another
          </Link>
        </div>
      </div>
    );
  }

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="bundle-file">Bundle file</Label>
        <input
          id="bundle-file"
          type="file"
          accept="application/json,.json"
          onChange={handleFile}
          className="block w-full text-sm text-foreground-muted"
        />
      </div>
      <div>
        <Label htmlFor="bundle">Or paste the bundle JSON</Label>
        <textarea
          ref={textareaRef}
          id="bundle"
          name="bundle"
          rows={16}
          spellCheck={false}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 font-mono text-xs text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
          placeholder='{"format": "icorepen.learning_path.v1", "path": {...}, "modules": [...]}'
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Importing..." : "Import path"}
      </Button>
    </form>
  );
}
