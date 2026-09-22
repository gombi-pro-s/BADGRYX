"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { FormError } from "@/components/ui/input";
import type { CheckoutState } from "./actions";

export function UpgradeButton({
  label,
  configured,
  onCheckout,
}: {
  label: string;
  configured: boolean;
  onCheckout: () => Promise<CheckoutState>;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (!configured) {
    return (
      <Button variant="secondary" disabled className="w-full">
        {label} (not configured)
      </Button>
    );
  }

  return (
    <div>
      <Button
        className="w-full"
        disabled={pending}
        onClick={() =>
          startTransition(async () => {
            // A successful checkout redirects server-side and never
            // returns here; a non-null result means it failed.
            const result = await onCheckout();
            setError(result.error);
          })
        }
      >
        {pending ? "Redirecting..." : label}
      </Button>
      <FormError>{error}</FormError>
    </div>
  );
}
