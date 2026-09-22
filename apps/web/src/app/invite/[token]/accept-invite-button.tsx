"use client";

import { useState, useTransition } from "react";
import { acceptInvitationAction } from "@/app/(app)/orgs/actions";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";

export function AcceptInviteButton({ token }: { token: string }) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div>
      <Button
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            const result = await acceptInvitationAction(token);
            // A successful accept redirects server-side and never returns
            // here; a non-null result means it failed.
            setError(result.error);
          })
        }
      >
        {pending ? "Joining..." : "Accept invitation"}
      </Button>
      <FormError>{error}</FormError>
    </div>
  );
}
