"use client";

import { useActionState, useState } from "react";
import { deleteMyAccountAction, type DeleteAccountState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: DeleteAccountState = { error: null };

export function DeleteAccountForm({ userEmail }: { userEmail: string }) {
  const [state, formAction, pending] = useActionState(deleteMyAccountAction, initialState);
  const [expanded, setExpanded] = useState(false);

  if (!expanded) {
    return (
      <Button variant="danger" onClick={() => setExpanded(true)}>
        Delete my account
      </Button>
    );
  }

  return (
    <form action={formAction} className="space-y-4">
      <p className="text-sm text-danger">
        This permanently deletes your account and every piece of data tied to it -- your profile, skill graph,
        lab and quiz history, CTF and investigation submissions, mentor conversations, scans, and subscription.
        This cannot be undone.
      </p>
      <div>
        <Label htmlFor="confirmation">
          Type <span className="font-mono text-foreground">{userEmail}</span> to confirm
        </Label>
        <Input id="confirmation" name="confirmation" required autoComplete="off" placeholder={userEmail} />
      </div>
      <FormError>{state.error}</FormError>
      <div className="flex gap-3">
        <Button type="submit" variant="danger" disabled={pending}>
          {pending ? "Deleting..." : "Permanently delete my account"}
        </Button>
        <Button type="button" variant="secondary" onClick={() => setExpanded(false)} disabled={pending}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
