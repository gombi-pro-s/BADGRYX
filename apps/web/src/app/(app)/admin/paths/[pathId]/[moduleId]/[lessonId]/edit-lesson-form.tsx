"use client";

import { useActionState } from "react";
import { updateLessonAction, type FormState } from "../../../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

interface Initial {
  slug: string;
  title: string;
  summary: string;
  content_markdown: string;
  estimated_minutes: number;
  title_es: string | null;
  content_markdown_es: string | null;
}

export function EditLessonForm({
  pathId,
  moduleId,
  lessonId,
  initial,
}: {
  pathId: string;
  moduleId: string;
  lessonId: string;
  initial: Initial;
}) {
  const action = updateLessonAction.bind(null, pathId, moduleId, lessonId);
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="estimated_minutes">Minutes</Label>
          <Input
            id="estimated_minutes"
            name="estimated_minutes"
            type="number"
            min={1}
            max={600}
            defaultValue={initial.estimated_minutes}
            required
          />
        </div>
      </div>
      <div>
        <Label htmlFor="slug">Slug</Label>
        <Input id="slug" name="slug" defaultValue={initial.slug} required pattern="[a-z0-9-]{3,64}" />
      </div>
      <div>
        <Label htmlFor="summary">Summary</Label>
        <Input id="summary" name="summary" defaultValue={initial.summary} maxLength={500} />
      </div>
      <div>
        <Label htmlFor="content_markdown">Content (Markdown)</Label>
        <textarea
          id="content_markdown"
          name="content_markdown"
          defaultValue={initial.content_markdown}
          required
          rows={16}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 font-mono text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <div className="rounded-md border border-border p-3">
        <p className="mb-3 text-xs font-medium text-foreground-subtle">
          Spanish translation (optional) &mdash; shown instead of the text above when a learner&apos;s language is
          set to Spanish. Leave both blank to remove the translation.
        </p>
        <div className="mb-3">
          <Label htmlFor="title_es">Title (Spanish)</Label>
          <Input id="title_es" name="title_es" defaultValue={initial.title_es ?? ""} maxLength={200} />
        </div>
        <div>
          <Label htmlFor="content_markdown_es">Content (Spanish, Markdown)</Label>
          <textarea
            id="content_markdown_es"
            name="content_markdown_es"
            defaultValue={initial.content_markdown_es ?? ""}
            rows={16}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 font-mono text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
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
