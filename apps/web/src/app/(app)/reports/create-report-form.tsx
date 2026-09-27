"use client";

import { useActionState } from "react";
import { createReportAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function CreateReportForm() {
  const [state, formAction, pending] = useActionState(createReportAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="title">Title</Label>
        <Input id="title" name="title" required maxLength={200} placeholder="Acme Corp internal pentest" />
      </div>
      <div>
        <Label htmlFor="kind">Kind</Label>
        <select
          id="kind"
          name="kind"
          defaultValue="pentest_report"
          className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        >
          <option value="pentest_report">Pentest report</option>
          <option value="methodology">Methodology write-up</option>
        </select>
      </div>
      <div>
        <Label htmlFor="content_markdown">Content (markdown)</Label>
        <textarea
          id="content_markdown"
          name="content_markdown"
          required
          rows={10}
          placeholder={"# Scope\n\n# Findings\n\n## Finding 1: ...\n- Severity:\n- Evidence:\n- Impact:\n- Remediation:"}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 font-mono text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create report"}
      </Button>
    </form>
  );
}
