"use client";

import { useActionState } from "react";
import { createAnnouncementAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function CreateAnnouncementForm() {
  const [state, formAction, pending] = useActionState(createAnnouncementAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="title">Title</Label>
        <Input id="title" name="title" required maxLength={200} />
      </div>
      <div>
        <Label htmlFor="body_markdown">Body (markdown)</Label>
        <textarea
          id="body_markdown"
          name="body_markdown"
          required
          rows={4}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <div>
        <Label htmlFor="expires_at">Expires at (optional)</Label>
        <Input id="expires_at" name="expires_at" type="datetime-local" />
      </div>
      <div className="rounded-md border border-border p-3">
        <p className="mb-3 text-xs font-medium text-foreground-subtle">
          Spanish translation (optional) &mdash; shown instead of the text above when a learner&apos;s language is
          set to Spanish. Leave blank for no translation.
        </p>
        <div className="mb-3">
          <Label htmlFor="title_es">Title (Spanish)</Label>
          <Input id="title_es" name="title_es" maxLength={200} />
        </div>
        <div>
          <Label htmlFor="body_markdown_es">Body (Spanish, markdown)</Label>
          <textarea
            id="body_markdown_es"
            name="body_markdown_es"
            rows={4}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create announcement"}
      </Button>
    </form>
  );
}
