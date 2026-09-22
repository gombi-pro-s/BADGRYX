"use client";

import { useActionState } from "react";
import { createOrganizationAction, type FormState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: FormState = { error: null };

export function CreateOrganizationForm() {
  const [state, formAction, pending] = useActionState(createOrganizationAction, initialState);

  return (
    <form action={formAction} className="space-y-4 rounded-lg border border-border bg-surface p-5">
      <h2 className="text-sm font-semibold text-foreground">Create an organization</h2>
      <div>
        <Label htmlFor="name">Name</Label>
        <Input id="name" name="name" required maxLength={200} placeholder="Acme Security" />
      </div>
      <div>
        <Label htmlFor="slug">Slug</Label>
        <Input id="slug" name="slug" required pattern="[a-z0-9-]{3,64}" placeholder="acme-security" />
        <p className="mt-1 text-xs text-foreground-subtle">Lowercase letters, numbers, hyphens only.</p>
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" disabled={pending}>
        {pending ? "Creating..." : "Create organization"}
      </Button>
    </form>
  );
}
