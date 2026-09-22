"use client";

import { useActionState } from "react";
import { reviewCapstoneSubmissionAction, type ReviewFormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";

const initialState: ReviewFormState = { error: null };

export function ReviewSubmissionForm({ submissionId, currentStatus }: { submissionId: string; currentStatus: string }) {
  const action = reviewCapstoneSubmissionAction.bind(null, submissionId);
  const [state, formAction, pending] = useActionState(action, initialState);

  if (currentStatus === "passed") {
    return <p className="text-xs text-success">Passed -- this submission cannot be re-reviewed.</p>;
  }

  return (
    <form action={formAction} className="space-y-2">
      <div className="flex gap-2">
        <select
          name="status"
          defaultValue="under_review"
          className="h-9 rounded-md border border-border bg-surface px-2 text-xs text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        >
          <option value="under_review">Mark under review</option>
          <option value="passed">Pass</option>
          <option value="needs_revision">Needs revision</option>
        </select>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Saving..." : "Submit review"}
        </Button>
      </div>
      <textarea
        name="notes"
        rows={2}
        maxLength={4000}
        placeholder="Reviewer notes (shown to the learner)"
        className="w-full rounded-md border border-border bg-surface px-2 py-1.5 text-xs text-foreground focus-visible:outline-2 focus-visible:outline-accent"
      />
      <FormError>{state.error}</FormError>
    </form>
  );
}
