"use client";

import { useActionState } from "react";
import { createLabAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { LabFormFields } from "./lab-form-fields";

const initialState: FormState = { error: null };

export function CreateLabForm() {
  const [state, formAction, pending] = useActionState(createLabAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <LabFormFields />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create lab"}
      </Button>
    </form>
  );
}
