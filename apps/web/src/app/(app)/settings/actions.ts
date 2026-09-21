"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export interface ProfileActionState {
  error: string | null;
  success?: boolean;
}

const profileSchema = z.object({
  display_name: z.string().trim().min(1, "Display name is required.").max(80),
  username: z
    .string()
    .trim()
    .regex(/^[a-zA-Z0-9_-]{3,32}$/, "3-32 characters: letters, numbers, - or _.")
    .or(z.literal("")),
  bio: z.string().trim().max(280).optional(),
  timezone: z.string().trim().max(64),
});

export async function updateProfileAction(
  _prevState: ProfileActionState,
  formData: FormData,
): Promise<ProfileActionState> {
  const user = await requireUser();

  const parsed = profileSchema.safeParse({
    display_name: formData.get("display_name"),
    username: formData.get("username"),
    bio: formData.get("bio"),
    timezone: formData.get("timezone"),
  });

  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "Invalid profile data." };
  }

  const supabase = await createClient();
  // RLS (profiles_update_own) independently enforces that this can only
  // ever affect the caller's own row -- the .eq("id", user.id) here is
  // belt-and-suspenders, not the actual security boundary.
  const { error } = await supabase
    .from("profiles")
    .update({
      display_name: parsed.data.display_name,
      username: parsed.data.username || null,
      bio: parsed.data.bio || null,
      timezone: parsed.data.timezone,
    })
    .eq("id", user.id);

  if (error) {
    if (error.code === "23505") {
      return { error: "That username is already taken." };
    }
    return { error: "Could not save your profile. Please try again." };
  }

  revalidatePath("/settings");
  return { error: null, success: true };
}
