"use client";

import { useActionState } from "react";
import { createCapstoneAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { CapstoneFormFields } from "./capstone-form-fields";

const initialState: FormState = { error: null };

export function CreateCapstoneForm() {
  const [state, formAction, pending] = useActionState(createCapstoneAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <CapstoneFormFields />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create capstone"}
      </Button>
    </form>
  );
}
