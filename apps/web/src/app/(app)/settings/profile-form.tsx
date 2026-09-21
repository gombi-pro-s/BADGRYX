"use client";

import { useActionState } from "react";
import { updateProfileAction, type ProfileActionState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const initialState: ProfileActionState = { error: null };

interface Initial {
  display_name: string;
  username: string;
  bio: string;
  timezone: string;
}

export function ProfileForm({ initial }: { initial: Initial }) {
  const [state, formAction, pending] = useActionState(updateProfileAction, initialState);

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <Label htmlFor="display_name">Display name</Label>
        <Input id="display_name" name="display_name" defaultValue={initial.display_name} required maxLength={80} />
      </div>
      <div>
        <Label htmlFor="username">Username</Label>
        <Input id="username" name="username" defaultValue={initial.username} placeholder="optional" />
      </div>
      <div>
        <Label htmlFor="bio">Bio</Label>
        <textarea
          id="bio"
          name="bio"
          defaultValue={initial.bio}
          maxLength={280}
          rows={3}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <div>
        <Label htmlFor="timezone">Timezone</Label>
        <Input id="timezone" name="timezone" defaultValue={initial.timezone} />
      </div>
      <FormError>{state.error}</FormError>
      {state.success && (
        <p className="rounded-md border border-success/30 bg-success-muted px-3 py-2 text-sm text-success">
          Saved.
        </p>
      )}
      <Button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save changes"}
      </Button>
    </form>
  );
}
