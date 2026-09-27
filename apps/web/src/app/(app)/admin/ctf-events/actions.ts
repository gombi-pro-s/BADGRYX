"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { logPublishToggle } from "@/lib/audit";
import type { CtfScoringType } from "@/types/database";

export interface FormState {
  error: string | null;
}

const SCORING_TYPES: CtfScoringType[] = ["static", "dynamic"];

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const eventSchema = z.object({
  slug: z.string().trim().regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, hyphens only."),
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(4000).optional(),
  scoring_type: z.enum(SCORING_TYPES as [CtfScoringType, ...CtfScoringType[]]),
  starts_at: z
    .string()
    .trim()
    .optional()
    .transform((v) => (v ? new Date(v).toISOString() : null)),
  ends_at: z
    .string()
    .trim()
    .optional()
    .transform((v) => (v ? new Date(v).toISOString() : null)),
});

export async function createEventAction(_prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = eventSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    scoring_type: formData.get("scoring_type"),
    starts_at: formData.get("starts_at"),
    ends_at: formData.get("ends_at"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };
  if (parsed.data.starts_at && parsed.data.ends_at && parsed.data.ends_at <= parsed.data.starts_at) {
    return { error: "End time must be after the start time." };
  }

  const supabase = await createClient();
  const { error } = await supabase.from("ctf_events").insert({
    slug: parsed.data.slug,
    title: parsed.data.title,
    description: parsed.data.description || null,
    scoring_type: parsed.data.scoring_type,
    starts_at: parsed.data.starts_at,
    ends_at: parsed.data.ends_at,
  });
  if (error) return { error: error.code === "23505" ? "That slug is already in use." : error.message };

  revalidatePath("/admin/ctf-events");
  return { error: null };
}

export async function updateEventAction(eventId: string, _prev: FormState, formData: FormData): Promise<FormState> {
  await requireAdmin();
  const parsed = eventSchema.safeParse({
    slug: formData.get("slug"),
    title: formData.get("title"),
    description: formData.get("description"),
    scoring_type: formData.get("scoring_type"),
    starts_at: formData.get("starts_at"),
    ends_at: formData.get("ends_at"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };
  if (parsed.data.starts_at && parsed.data.ends_at && parsed.data.ends_at <= parsed.data.starts_at) {
    return { error: "End time must be after the start time." };
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("ctf_events")
    .update({
      slug: parsed.data.slug,
      title: parsed.data.title,
      description: parsed.data.description || null,
      scoring_type: parsed.data.scoring_type,
      starts_at: parsed.data.starts_at,
      ends_at: parsed.data.ends_at,
    })
    .eq("id", eventId);
  if (error) return { error: error.message };

  revalidatePath("/admin/ctf-events");
  revalidatePath(`/admin/ctf-events/${eventId}`);
  return { error: null };
}

export async function toggleEventPublishedAction(eventId: string, published: boolean) {
  await requireAdmin();
  const supabase = await createClient();
  const { error } = await supabase.from("ctf_events").update({ published }).eq("id", eventId);
  if (error) throw new Error(error.message);
  await logPublishToggle(supabase, "ctf_event", eventId, published);
  revalidatePath("/admin/ctf-events");
  revalidatePath(`/admin/ctf-events/${eventId}`);
}
