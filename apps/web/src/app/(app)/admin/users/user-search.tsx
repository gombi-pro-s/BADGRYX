"use client";

import { useActionState } from "react";
import { searchUsersAction, type SearchState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";
import { RoleToggle } from "./role-toggle";
import type { PlatformRole } from "@/types/database";

const GRANTABLE_ROLES: PlatformRole[] = ["instructor", "moderator", "admin"];

const initialState: SearchState = { results: [], error: null };

export function UserSearch({ currentAdminId }: { currentAdminId: string }) {
  const [state, formAction, pending] = useActionState(searchUsersAction, initialState);

  return (
    <div>
      <form action={formAction} className="mb-6 flex items-end gap-3">
        <div className="flex-1">
          <Label htmlFor="query">Search by email, username, or display name</Label>
          <Input id="query" name="query" placeholder="alice@example.com" />
        </div>
        <Button type="submit" disabled={pending}>
          {pending ? "Searching..." : "Search"}
        </Button>
      </form>
      <FormError>{state.error}</FormError>

      {state.results.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {state.results.map((user) => (
            <li key={user.user_id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-medium text-foreground">
                  {user.display_name ?? user.username ?? user.email ?? user.user_id}
                </p>
                <p className="truncate text-xs text-foreground-subtle">{user.email}</p>
              </div>
              <div className="flex shrink-0 gap-1.5">
                {GRANTABLE_ROLES.map((role) => (
                  <RoleToggle
                    key={role}
                    userId={user.user_id}
                    role={role}
                    granted={user.roles.includes(role)}
                    disabled={role === "admin" && user.user_id === currentAdminId}
                    disabledReason="You can't revoke your own admin role -- ask another admin."
                  />
                ))}
              </div>
            </li>
          ))}
        </ul>
      ) : (
        !pending && (
          <p className="text-sm text-foreground-muted">
            {state.error ? "" : "Search for a user to view or change their roles."}
          </p>
        )
      )}
    </div>
  );
}
