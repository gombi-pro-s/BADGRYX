import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

export interface MentorQuota {
  allowed: boolean;
  used: number;
  limit: number;
}

const DEFAULT_LIMIT_IF_UNSET = 10;

/**
 * Enforces the real entitlement engine (get_entitlement -> plan_entitlements,
 * see 20260921000011_entitlements.sql) for the AI Mentor, rather than a
 * separate, disconnected rate limiter. A user's plan controls their daily
 * Mentor budget the same way it controls every other gated feature.
 *
 * "Today" is a UTC calendar day boundary. This is a deliberate
 * simplification (not per-user-timezone) -- documented here rather than
 * silently wrong, and cheap to change later if it matters.
 */
export async function checkMentorQuota(
  supabase: SupabaseClient<Database>,
  userId: string,
): Promise<MentorQuota> {
  const { data: limitRaw } = await supabase.rpc("get_entitlement", {
    p_subject_type: "user",
    p_subject_id: userId,
    p_key: "ai_mentor_daily_requests",
  });

  const limit =
    typeof limitRaw === "number"
      ? limitRaw
      : typeof limitRaw === "string" && !Number.isNaN(Number(limitRaw))
        ? Number(limitRaw)
        : DEFAULT_LIMIT_IF_UNSET;

  const startOfDayUtc = new Date();
  startOfDayUtc.setUTCHours(0, 0, 0, 0);

  const { count, error } = await supabase
    .from("mentor_messages")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("role", "user")
    .gte("created_at", startOfDayUtc.toISOString());

  if (error) {
    throw new Error(`Failed to check Mentor quota: ${error.message}`);
  }

  const used = count ?? 0;
  return { allowed: used < limit, used, limit };
}
