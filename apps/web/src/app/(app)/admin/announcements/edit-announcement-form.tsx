"use client";

import { useActionState } from "react";
import { updateAnnouncementAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function EditAnnouncementForm({
  announcementId,
  initial,
}: {
  announcementId: string;
  initial: { title: string; body_markdown: string; expires_at: string | null };
}) {
  const [state, formAction, pending] = useActionState(updateAnnouncementAction.bind(null, announcementId), initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="title">Title</Label>
        <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
      </div>
      <div>
        <Label htmlFor="body_markdown">Body (markdown)</Label>
        <textarea
          id="body_markdown"
          name="body_markdown"
          defaultValue={initial.body_markdown}
          required
          rows={4}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <div>
        <Label htmlFor="expires_at">Expires at (optional)</Label>
        <Input
          id="expires_at"
          name="expires_at"
          type="datetime-local"
          defaultValue={initial.expires_at ? initial.expires_at.slice(0, 16) : ""}
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
