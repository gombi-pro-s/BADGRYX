"use client";

import { useActionState } from "react";
import { updateCapstoneAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { CapstoneFormFields } from "../capstone-form-fields";

const initialState: FormState = { error: null };

interface Initial {
  slug: string;
  title: string;
  description: string;
  report_required: boolean;
}

export function EditCapstoneForm({ capstoneId, initial }: { capstoneId: string; initial: Initial }) {
  const action = updateCapstoneAction.bind(null, capstoneId);
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <CapstoneFormFields initial={initial} />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
