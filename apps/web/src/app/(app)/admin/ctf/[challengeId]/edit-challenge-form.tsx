"use client";

import { useActionState } from "react";
import { updateChallengeAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import { ChallengeFormFields } from "../challenge-form-fields";
import type { DifficultyLevel, LabCategory } from "@/types/database";

const initialState: FormState = { error: null };

interface Initial {
  slug: string;
  title: string;
  description: string;
  category: LabCategory;
  difficulty: DifficultyLevel;
  points: number;
  min_points: number | null;
  event_id: string | null;
}

export function EditChallengeForm({
  challengeId,
  initial,
  events,
}: {
  challengeId: string;
  initial: Initial;
  events: { id: string; title: string }[];
}) {
  const action = updateChallengeAction.bind(null, challengeId);
  const [state, formAction, pending] = useActionState(action, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <ChallengeFormFields initial={initial} flagOptional events={events} />
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
