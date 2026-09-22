"use client";

import { useState, useTransition } from "react";
import { updateMemberRoleAction, removeMemberAction } from "../actions";
import type { OrgRole } from "@/types/database";

const ROLES: OrgRole[] = ["member", "instructor", "team_owner", "org_admin"];

export function MemberRoleSelect({
  organizationId,
  memberId,
  currentRole,
}: {
  organizationId: string;
  memberId: string;
  currentRole: OrgRole;
}) {
  const [pending, startTransition] = useTransition();
  const [role, setRole] = useState(currentRole);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="flex flex-col items-end gap-1">
      <select
        value={role}
        disabled={pending}
        onChange={(e) => {
          const next = e.target.value as OrgRole;
          const previous = role;
          setRole(next);
          startTransition(async () => {
            const result = await updateMemberRoleAction(organizationId, memberId, next);
            if (result.error) {
              setRole(previous);
              setError(result.error);
            } else {
              setError(null);
            }
          });
        }}
        className="h-8 rounded-md border border-border bg-surface px-2 text-xs text-foreground focus-visible:outline-2 focus-visible:outline-accent disabled:opacity-50"
      >
        {ROLES.map((r) => (
          <option key={r} value={r}>
            {r.replace("_", " ")}
          </option>
        ))}
      </select>
      {error && <p className="max-w-40 text-right text-xs text-danger">{error}</p>}
    </div>
  );
}

export function RemoveMemberButton({
  organizationId,
  memberId,
  isSelf,
}: {
  organizationId: string;
  memberId: string;
  isSelf: boolean;
}) {
  const [pending, startTransition] = useTransition();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!confirming) {
    return (
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className="shrink-0 text-xs font-medium text-danger hover:underline"
      >
        {isSelf ? "Leave" : "Remove"}
      </button>
    );
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <div className="flex items-center gap-2">
        <span className="text-xs text-foreground-subtle">{isSelf ? "Leave org?" : "Remove?"}</span>
        <button
          type="button"
          disabled={pending}
          onClick={() =>
            startTransition(async () => {
              const result = await removeMemberAction(organizationId, memberId);
              if (result.error) {
                setError(result.error);
                setConfirming(false);
              }
            })
          }
          className="text-xs font-medium text-danger hover:underline disabled:opacity-50"
        >
          {pending ? "..." : "Yes"}
        </button>
        <button
          type="button"
          onClick={() => setConfirming(false)}
          className="text-xs text-foreground-subtle hover:underline"
        >
          Cancel
        </button>
      </div>
      {error && <p className="max-w-48 text-right text-xs text-danger">{error}</p>}
    </div>
  );
}
