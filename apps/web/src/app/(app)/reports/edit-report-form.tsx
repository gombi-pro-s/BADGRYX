"use client";

import { useActionState } from "react";
import { updateReportAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function EditReportForm({
  reportId,
  initial,
}: {
  reportId: string;
  initial: { title: string; kind: string; content_markdown: string };
}) {
  const [state, formAction, pending] = useActionState(updateReportAction.bind(null, reportId), initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="title">Title</Label>
        <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
      </div>
      <div>
        <Label htmlFor="kind">Kind</Label>
        <select
          id="kind"
          name="kind"
          defaultValue={initial.kind}
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
          defaultValue={initial.content_markdown}
          required
          rows={16}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 font-mono text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
