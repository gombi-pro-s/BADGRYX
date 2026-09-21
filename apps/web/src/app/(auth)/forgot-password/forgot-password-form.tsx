"use client";

import { useActionState } from "react";
import { requestPasswordResetAction, type AuthActionState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: AuthActionState & { submitted?: boolean } = { error: null };

export function ForgotPasswordForm() {
  const [state, formAction, pending] = useActionState(async (prev: AuthActionState, fd: FormData) => {
    const result = await requestPasswordResetAction(prev, fd);
    return { ...result, submitted: result.error === null };
  }, initialState);

  if (state.submitted) {
    return (
      <p className="rounded-md border border-success/30 bg-success-muted px-3 py-2 text-sm text-success">
        If an account exists for that email, a reset link is on its way.
      </p>
    );
  }

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="email">Email</Label>
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Sending..." : "Send reset link"}
      </Button>
    </form>
  );
}
