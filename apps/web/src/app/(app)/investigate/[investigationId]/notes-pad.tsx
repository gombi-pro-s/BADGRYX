"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

const SAVE_DEBOUNCE_MS = 1000;

export function NotesPad({ investigationId, userId, initialNotes }: { investigationId: string; userId: string; initialNotes: string }) {
  const [notes, setNotes] = useState(initialNotes);
  const [status, setStatus] = useState<"idle" | "saving" | "saved" | "error">("idle");
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  function scheduleSave(next: string) {
    setNotes(next);
    setStatus("idle");
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(async () => {
      setStatus("saving");
      const supabase = createClient();
      const { error } = await supabase
        .from("investigation_instances")
        .upsert({ investigation_id: investigationId, user_id: userId, notes: next }, { onConflict: "investigation_id,user_id" });
      setStatus(error ? "error" : "saved");
    }, SAVE_DEBOUNCE_MS);
  }

  return (
    <div className="rounded-lg border border-border bg-surface p-6">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-sm font-semibold text-foreground">Your notes</h3>
        <span className="text-xs text-foreground-subtle">
          {status === "saving" && "Saving..."}
          {status === "saved" && "Saved"}
          {status === "error" && <span className="text-danger">Could not save</span>}
        </span>
      </div>
      <p className="mb-3 text-xs text-foreground-subtle">
        Private working notes -- only you can see these, not even staff. Not graded; use them to track what you&apos;ve
        found while you work through the evidence.
      </p>
      <textarea
        value={notes}
        onChange={(e) => scheduleSave(e.target.value)}
        rows={8}
        maxLength={20000}
        placeholder="e.g. domain registered 3 days before the phishing email was sent..."
        className="w-full resize-y rounded-md border border-border bg-background-subtle px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
      />
    </div>
  );
}
