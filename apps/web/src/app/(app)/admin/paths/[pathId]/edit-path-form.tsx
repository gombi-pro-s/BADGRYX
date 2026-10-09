"use client";

import { useActionState } from "react";
import { updatePathAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function EditPathForm({
  pathId,
  initial,
}: {
  pathId: string;
  initial: {
    slug: string;
    title: string;
    description: string;
    title_es: string | null;
    description_es: string | null;
  };
}) {
  const action = updatePathAction.bind(null, pathId);
  const [state, formAction, pending] = useActionState(action, initialState);

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
        <Label htmlFor="description">Description</Label>
        <textarea
          id="description"
          name="description"
          defaultValue={initial.description}
          rows={2}
          maxLength={2000}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <div className="rounded-md border border-border p-3">
        <p className="mb-3 text-xs font-medium text-foreground-subtle">
          Spanish translation (optional) &mdash; shown instead of the text above when a learner&apos;s language is
          set to Spanish. Leave the title blank to remove the translation.
        </p>
        <div className="mb-3">
          <Label htmlFor="title_es">Title (Spanish)</Label>
          <Input id="title_es" name="title_es" defaultValue={initial.title_es ?? ""} maxLength={200} />
        </div>
        <div>
          <Label htmlFor="description_es">Description (Spanish)</Label>
          <textarea
            id="description_es"
            name="description_es"
            defaultValue={initial.description_es ?? ""}
            rows={2}
            maxLength={2000}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
