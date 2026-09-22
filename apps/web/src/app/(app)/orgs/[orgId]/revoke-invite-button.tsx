"use client";

import { useTransition } from "react";

export function RevokeInviteButton({ onRevoke }: { onRevoke: () => Promise<void> }) {
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={pending}
      onClick={() => startTransition(onRevoke)}
      className="shrink-0 text-xs font-medium text-danger hover:underline disabled:opacity-50"
    >
      {pending ? "Revoking..." : "Revoke"}
    </button>
  );
}
