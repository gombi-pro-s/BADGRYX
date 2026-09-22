"use client";

import { useActionState, useState } from "react";
import { createInvitationAction, type InviteFormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";
import type { OrgRole } from "@/types/database";

const ROLES: OrgRole[] = ["member", "instructor", "team_owner", "org_admin"];

const initialState: InviteFormState = { error: null, inviteLink: null };

export function InviteForm({ organizationId }: { organizationId: string }) {
  const action = createInvitationAction.bind(null, organizationId);
  const [state, formAction, pending] = useActionState(action, initialState);
  const [copied, setCopied] = useState(false);

  return (
    <div className="rounded-lg border border-border bg-surface p-5">
      <h2 className="text-sm font-semibold text-foreground">Invite a member</h2>
      <p className="mt-1 text-xs text-foreground-subtle">
        There is no email service wired up yet -- the invite link is shown once below. Copy it and send it to the
        invitee yourself (see docs/adr/0010-org-invitations-manual-link.md).
      </p>
      <form action={formAction} className="mt-4 space-y-4">
        <div>
          <Label htmlFor="email">Email</Label>
          <Input id="email" name="email" type="email" required placeholder="person@example.com" />
        </div>
        <div>
          <Label htmlFor="role">Role</Label>
          <select
            id="role"
            name="role"
            defaultValue="member"
            className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          >
            {ROLES.map((r) => (
              <option key={r} value={r}>
                {r.replace("_", " ")}
              </option>
            ))}
          </select>
        </div>
        <FormError>{state.error}</FormError>
        <Button type="submit" disabled={pending}>
          {pending ? "Creating invite..." : "Create invite link"}
        </Button>
      </form>

      {state.inviteLink && (
        <div className="mt-4 rounded-md border border-success/30 bg-success-muted p-3">
          <p className="mb-1.5 text-xs font-medium text-success">
            Invite link created -- this is the only time it will be shown. Copy it now.
          </p>
          <div className="flex gap-2">
            <Input readOnly value={state.inviteLink} onFocus={(e) => e.currentTarget.select()} />
            <Button
              type="button"
              variant="secondary"
              onClick={() => {
                navigator.clipboard.writeText(state.inviteLink ?? "");
                setCopied(true);
              }}
            >
              {copied ? "Copied" : "Copy"}
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
