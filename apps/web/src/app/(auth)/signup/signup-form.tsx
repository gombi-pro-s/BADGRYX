"use client";

import { useActionState } from "react";
import { signUpAction, type AuthActionState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: AuthActionState = { error: null };

export function SignupForm() {
  const [state, formAction, pending] = useActionState(signUpAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="email">Email</Label>
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </div>
      <div>
        <Label htmlFor="password">Password</Label>
        <Input id="password" name="password" type="password" autoComplete="new-password" required minLength={12} />
        <p className="mt-1.5 text-xs text-foreground-subtle">
          At least 12 characters, with uppercase, lowercase, and a number.
        </p>
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Creating account..." : "Create account"}
      </Button>
      <p className="text-center text-xs text-foreground-subtle">
        By continuing you agree this account is for authorized security learning and testing only,
        as described in our acceptable use policy.
      </p>
    </form>
  );
}
