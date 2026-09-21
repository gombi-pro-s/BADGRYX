"use client";

import { useActionState } from "react";
import { updatePasswordAction, type AuthActionState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: AuthActionState = { error: null };

export default function UpdatePasswordPage() {
  const [state, formAction, pending] = useActionState(updatePasswordAction, initialState);

  return (
    <div>
      <h1 className="text-xl font-semibold text-foreground">Set a new password</h1>
      <p className="mt-1 text-sm text-foreground-muted">
        You followed a valid password reset link. Choose a new password below.
      </p>
      <form action={formAction} className="mt-6 space-y-4">
        <div>
          <Label htmlFor="password">New password</Label>
          <Input id="password" name="password" type="password" autoComplete="new-password" required minLength={12} />
        </div>
        <FormError>{state.error}</FormError>
        <Button type="submit" className="w-full" disabled={pending}>
          {pending ? "Updating..." : "Update password"}
        </Button>
      </form>
    </div>
  );
}
