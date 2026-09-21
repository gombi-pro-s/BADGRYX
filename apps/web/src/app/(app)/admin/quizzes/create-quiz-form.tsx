"use client";

import { useActionState } from "react";
import { createQuizAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function CreateQuizForm() {
  const [state, formAction, pending] = useActionState(createQuizAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="slug">Slug</Label>
          <Input id="slug" name="slug" required pattern="[a-z0-9-]{3,64}" placeholder="sqli-quiz" />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-3">
        <div>
          <Label htmlFor="passing_score">Passing score (%)</Label>
          <Input id="passing_score" name="passing_score" type="number" min={0} max={100} defaultValue={70} required />
        </div>
        <div>
          <Label htmlFor="hint_policy">Hint policy</Label>
          <select
            id="hint_policy"
            name="hint_policy"
            defaultValue="full"
            className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          >
            <option value="full">Full</option>
            <option value="limited">Limited</option>
            <option value="none">None</option>
          </select>
        </div>
        <div>
          <Label htmlFor="time_limit_minutes">Time limit (min, optional)</Label>
          <Input id="time_limit_minutes" name="time_limit_minutes" type="number" min={1} max={600} />
        </div>
      </div>
      <label className="flex items-center gap-2 text-sm text-foreground-muted">
        <input type="checkbox" name="is_exam" className="h-4 w-4 rounded border-border" />
        This is an exam (records &quot;assessment&quot; skill evidence instead of &quot;quiz&quot;)
      </label>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create quiz"}
      </Button>
    </form>
  );
}
