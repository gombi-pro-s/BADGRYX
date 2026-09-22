"use client";

import { useState, useTransition } from "react";
import { grantRoleAction, revokeRoleAction } from "./actions";
import type { PlatformRole } from "@/types/database";

export function RoleToggle({
  userId,
  role,
  granted,
  disabled,
  disabledReason,
}: {
  userId: string;
  role: PlatformRole;
  granted: boolean;
  disabled?: boolean;
  disabledReason?: string;
}) {
  const [optimistic, setOptimistic] = useState(granted);
  const [pending, startTransition] = useTransition();

  return (
    <button
      type="button"
      disabled={disabled || pending}
      title={disabled ? disabledReason : undefined}
      onClick={() => {
        const next = !optimistic;
        setOptimistic(next);
        startTransition(async () => {
          try {
            if (next) {
              await grantRoleAction(userId, role);
            } else {
              await revokeRoleAction(userId, role);
            }
          } catch {
            setOptimistic(!next); // revert on failure
          }
        });
      }}
      className={`rounded-full border px-2.5 py-0.5 text-xs font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-50 ${
        optimistic
          ? "border-accent bg-accent-muted text-accent"
          : "border-border text-foreground-muted hover:border-border-strong"
      }`}
    >
      {role}
    </button>
  );
}
