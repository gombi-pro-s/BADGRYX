"use client";

import { useActionState } from "react";
import { updateLabAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { LabFormFields } from "../lab-form-fields";
import type { DifficultyLevel, LabCategory } from "@/types/database";

const initialState: FormState = { error: null };

interface Initial {
  slug: string;
  title: string;
  description: string;
  category: LabCategory;
  difficulty: DifficultyLevel;
  estimated_minutes: number;
  points: number;
}

export function EditLabForm({ labId, initial }: { labId: string; initial: Initial }) {
  const action = updateLabAction.bind(null, labId);
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <LabFormFields initial={initial} />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
