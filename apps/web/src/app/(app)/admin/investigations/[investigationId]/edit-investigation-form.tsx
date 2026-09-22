"use client";

import { useActionState } from "react";
import { updateInvestigationAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { InvestigationFormFields } from "../investigation-form-fields";
import type { DifficultyLevel, LabCategory } from "@/types/database";

const initialState: FormState = { error: null };

interface Initial {
  slug: string;
  title: string;
  briefing: string;
  category: LabCategory;
  difficulty: DifficultyLevel;
  estimated_minutes: number;
  points: number;
  passing_score: number;
}

export function EditInvestigationForm({ investigationId, initial }: { investigationId: string; initial: Initial }) {
  const action = updateInvestigationAction.bind(null, investigationId);
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <InvestigationFormFields initial={initial} />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
