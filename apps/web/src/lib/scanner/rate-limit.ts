import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";

export interface ScannerQuota {
  allowed: boolean;
  used: number;
  limit: number;
}

const DEFAULT_LIMIT_IF_UNSET = 5;

/**
 * Enforces the real entitlement engine (get_entitlement -> plan_entitlements)
 * for the security scanner, mirroring lib/mentor/rate-limit.ts's
 * checkMentorQuota -- a user's plan controls their daily scan budget the
 * same way it controls every other gated feature, not a separate ad hoc
 * limiter.
 *
 * "Today" is a UTC calendar day boundary, same deliberate simplification as
 * the Mentor's quota check.
 */
export async function checkScannerQuota(
  supabase: SupabaseClient<Database>,
  userId: string,
): Promise<ScannerQuota> {
  const { data: limitRaw } = await supabase.rpc("get_entitlement", {
    p_subject_type: "user",
    p_subject_id: userId,
    p_key: "scanner_daily_scans",
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
    .from("scans")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", startOfDayUtc.toISOString());

  if (error) {
    throw new Error(`Failed to check scanner quota: ${error.message}`);
  }

  const used = count ?? 0;
  return { allowed: used < limit, used, limit };
}
