"use client";

import { useActionState } from "react";
import { createInvestigationAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { InvestigationFormFields } from "./investigation-form-fields";

const initialState: FormState = { error: null };

export function CreateInvestigationForm() {
  const [state, formAction, pending] = useActionState(createInvestigationAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <InvestigationFormFields />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create investigation"}
      </Button>
    </form>
  );
}
