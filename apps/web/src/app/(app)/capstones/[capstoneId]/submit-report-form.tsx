"use client";

import { useActionState } from "react";
import { submitCapstoneReportAction, type SubmitFormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";

const initialState: SubmitFormState = { error: null };

export function SubmitReportForm({ capstoneId }: { capstoneId: string }) {
  const action = submitCapstoneReportAction.bind(null, capstoneId);
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <textarea
        name="report_content"
        rows={12}
        maxLength={20000}
        required
        placeholder="Write your report: what you did, how you did it, what you found, and how you'd remediate it."
        className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
      />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Submitting..." : "Submit report"}
      </Button>
    </form>
  );
}
