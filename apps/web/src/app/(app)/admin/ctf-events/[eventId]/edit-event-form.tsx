"use client";

import { useActionState } from "react";
import { updateEventAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

interface Initial {
  title: string;
  slug: string;
  description: string;
  scoring_type: string;
  starts_at: string | null;
  ends_at: string | null;
}

export function EditEventForm({ eventId, initial }: { eventId: string; initial: Initial }) {
  const [state, formAction, pending] = useActionState(updateEventAction.bind(null, eventId), initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="slug">Slug</Label>
          <Input id="slug" name="slug" defaultValue={initial.slug} required pattern="[a-z0-9-]{3,64}" />
        </div>
      </div>
      <div>
        <Label htmlFor="scoring_type">Scoring</Label>
        <select
          id="scoring_type"
          name="scoring_type"
          defaultValue={initial.scoring_type}
          className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        >
          <option value="static">Static (each challenge is worth its fixed points)</option>
          <option value="dynamic">Dynamic</option>
        </select>
        <p className="mt-1.5 text-xs text-foreground-subtle">
          Dynamic scoring is not implemented yet -- challenges still score at their fixed points either way.
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="starts_at">Starts at (optional)</Label>
          <Input
            id="starts_at"
            name="starts_at"
            type="datetime-local"
            defaultValue={initial.starts_at ? initial.starts_at.slice(0, 16) : ""}
          />
        </div>
        <div>
          <Label htmlFor="ends_at">Ends at (optional)</Label>
          <Input
            id="ends_at"
            name="ends_at"
            type="datetime-local"
            defaultValue={initial.ends_at ? initial.ends_at.slice(0, 16) : ""}
          />
        </div>
      </div>
      <div>
        <Label htmlFor="description">Description</Label>
        <textarea
          id="description"
          name="description"
          defaultValue={initial.description}
          rows={3}
          maxLength={4000}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
