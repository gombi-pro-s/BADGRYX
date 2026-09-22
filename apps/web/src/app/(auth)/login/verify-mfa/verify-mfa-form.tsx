"use client";

import { useActionState } from "react";
import { verifyMfaChallengeAction, type AuthActionState } from "../../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: AuthActionState = { error: null };

export function VerifyMfaForm({ next }: { next?: string }) {
  const [state, formAction, pending] = useActionState(verifyMfaChallengeAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <input type="hidden" name="next" value={next ?? "/dashboard"} />
      <div>
        <Label htmlFor="code">Authentication code</Label>
        <Input
          id="code"
          name="code"
          type="text"
          inputMode="numeric"
          pattern="[0-9]{6}"
          maxLength={6}
          autoComplete="one-time-code"
          placeholder="123456"
          required
          autoFocus
        />
      </div>
      <FormError>{state.error}</FormError>
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? "Verifying..." : "Verify"}
      </Button>
    </form>
  );
}
