"use client";

import { useEffect, useRef } from "react";
import { createClient } from "@/lib/supabase/client";

/**
 * Marks the lesson as read once per mount. Writes directly to
 * lesson_progress via the browser client -- RLS's lesson_progress_own
 * policy (owner may write their own row) is the actual enforcement, same
 * as everywhere else in this app; this is UX convenience, not the
 * "theory" skill evidence gate (that requires passing the lesson's quiz).
 */
export function MarkRead({ userId, lessonId }: { userId: string; lessonId: string }) {
  const marked = useRef(false);

  useEffect(() => {
    if (marked.current) return;
    marked.current = true;
    const supabase = createClient();
    supabase
      .from("lesson_progress")
      .upsert(
        { user_id: userId, lesson_id: lessonId, completed_at: new Date().toISOString() },
        { onConflict: "user_id,lesson_id" },
      )
      .then();
  }, [userId, lessonId]);

  return null;
}
