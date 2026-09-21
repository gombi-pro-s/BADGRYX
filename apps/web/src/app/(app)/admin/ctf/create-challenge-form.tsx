"use client";

import { useActionState } from "react";
import { createChallengeAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { ChallengeFormFields } from "./challenge-form-fields";

const initialState: FormState = { error: null };

export function CreateChallengeForm() {
  const [state, formAction, pending] = useActionState(createChallengeAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <ChallengeFormFields />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create challenge"}
      </Button>
    </form>
  );
}
