"use client";

import { useActionState } from "react";
import { createEventAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function CreateEventForm() {
  const [state, formAction, pending] = useActionState(createEventAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="slug">Slug</Label>
          <Input id="slug" name="slug" required pattern="[a-z0-9-]{3,64}" placeholder="spring-ctf" />
        </div>
      </div>
      <div>
        <Label htmlFor="scoring_type">Scoring</Label>
        <select
          id="scoring_type"
          name="scoring_type"
          defaultValue="static"
          className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        >
          <option value="static">Static (each challenge is worth its fixed points)</option>
          <option value="dynamic">Dynamic</option>
        </select>
        <p className="mt-1.5 text-xs text-foreground-subtle">
          Dynamic scoring decays each challenge in this event from its Points down to its own Min points floor
          (set per challenge, defaulting to half of Points) over its first 10 solves. Each solver&apos;s own score is
          frozen at whatever the value was the moment they solved it.
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="starts_at">Starts at (optional)</Label>
          <Input id="starts_at" name="starts_at" type="datetime-local" />
        </div>
        <div>
          <Label htmlFor="ends_at">Ends at (optional)</Label>
          <Input id="ends_at" name="ends_at" type="datetime-local" />
        </div>
      </div>
      <div>
        <Label htmlFor="description">Description</Label>
        <textarea
          id="description"
          name="description"
          rows={3}
          maxLength={4000}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create event"}
      </Button>
    </form>
  );
}
