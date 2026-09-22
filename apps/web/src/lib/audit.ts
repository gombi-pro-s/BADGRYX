import "server-only";

import type { createClient } from "@/lib/supabase/server";

type SupabaseServerClient = Awaited<ReturnType<typeof createClient>>;

/**
 * Fire-and-forget audit logging for actions that don't already go through a
 * dedicated SECURITY DEFINER function -- mirrors the existing app-code
 * pattern in api/mentor/chat and api/scanner/scan (log_audit_event() is
 * already GRANTed to authenticated, and itself stamps actor/role/time, so
 * there's no reason to wrap it in a new SQL function just to call it from
 * here). A logging failure never blocks the action it's describing -- the
 * write already happened; losing the audit trail entry is a lesser failure
 * than reverting a successful admin action.
 */
export async function logAuditEvent(
  supabase: SupabaseServerClient,
  action: string,
  targetType: string,
  targetId: string,
  organizationId: string | null = null,
  metadata: Record<string, unknown> = {},
) {
  const { error } = await supabase.rpc("log_audit_event", {
    p_action: action,
    p_target_type: targetType,
    p_target_id: targetId,
    p_organization_id: organizationId,
    p_metadata: metadata,
  });
  if (error) {
    console.error(`Failed to log audit event ${action}:`, error);
  }
}

/** For the 8 near-identical admin publish/unpublish toggles across content types. */
export async function logPublishToggle(
  supabase: SupabaseServerClient,
  contentType: string,
  contentId: string,
  published: boolean,
) {
  await logAuditEvent(supabase, published ? `${contentType}.published` : `${contentType}.unpublished`, contentType, contentId);
}
