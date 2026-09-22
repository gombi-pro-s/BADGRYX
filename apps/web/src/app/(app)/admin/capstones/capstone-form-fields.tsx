import { Input, Label } from "@/components/ui/input";

interface Initial {
  slug?: string;
  title?: string;
  description?: string;
  report_required?: boolean;
}

export function CapstoneFormFields({ initial = {} }: { initial?: Initial }) {
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="slug">Slug</Label>
          <Input id="slug" name="slug" defaultValue={initial.slug} required pattern="[a-z0-9-]{3,64}" placeholder="web-app-pentest-capstone" />
        </div>
      </div>
      <div>
        <Label htmlFor="description">Description (markdown)</Label>
        <textarea
          id="description"
          name="description"
          defaultValue={initial.description}
          rows={6}
          maxLength={8000}
          placeholder="What the learner needs to deliver, and what a passing submission looks like."
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <label className="flex items-center gap-2 text-sm text-foreground-muted">
        <input
          type="checkbox"
          name="report_required"
          defaultChecked={initial.report_required ?? true}
          className="h-4 w-4 rounded border-border"
        />
        A written report is required to submit
      </label>
    </>
  );
}
