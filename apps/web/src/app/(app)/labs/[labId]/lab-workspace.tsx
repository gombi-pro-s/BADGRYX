"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

interface Hint {
  id: string;
  level: number;
  point_cost: number;
}

interface Instance {
  id: string;
  guided: boolean;
  status: string;
}

export function LabWorkspace({
  labId,
  userId,
  hints,
  initialInstance,
}: {
  labId: string;
  userId: string;
  hints: Hint[];
  initialInstance: Instance | null;
}) {
  const [instance, setInstance] = useState<Instance | null>(initialInstance);
  const [starting, setStarting] = useState<"guided" | "unguided" | null>(null);
  const [unlockedContent, setUnlockedContent] = useState<Record<string, string>>({});
  const [unlockingId, setUnlockingId] = useState<string | null>(null);
  const [flag, setFlag] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<{ correct: boolean } | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function startLab(guided: boolean) {
    setStarting(guided ? "guided" : "unguided");
    setError(null);
    const supabase = createClient();
    const { data, error: insertError } = await supabase
      .from("lab_instances")
      .insert({ lab_id: labId, user_id: userId, guided, status: "running" })
      .select("id, guided, status")
      .single();
    setStarting(null);
    if (insertError || !data) {
      setError(insertError?.message ?? "Failed to start lab.");
      return;
    }
    setInstance(data);
  }

  async function unlockHint(hintId: string) {
    setUnlockingId(hintId);
    setError(null);
    const supabase = createClient();
    const { error: rpcError } = await supabase.rpc("unlock_lab_hint", {
      p_lab_instance_id: instance!.id,
      p_hint_id: hintId,
    });
    if (rpcError) {
      setUnlockingId(null);
      setError(rpcError.message);
      return;
    }
    const { data: hint } = await supabase.from("lab_hints").select("content").eq("id", hintId).single();
    setUnlockingId(null);
    setUnlockedContent((prev) => ({ ...prev, [hintId]: hint?.content ?? "" }));
  }

  async function submitFlag() {
    setSubmitting(true);
    setError(null);
    const supabase = createClient();
    const { data, error: rpcError } = await supabase.rpc("submit_lab_flag", {
      p_lab_instance_id: instance!.id,
      p_flag: flag,
    });
    setSubmitting(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    const submission = data as unknown as { correct: boolean };
    setResult({ correct: submission.correct });
    if (!submission.correct) setFlag("");
  }

  if (!instance) {
    return (
      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-2 text-sm font-semibold text-foreground">Start this lab</h3>
        <p className="mb-4 text-sm text-foreground-muted">
          Guided records &quot;guided_lab&quot; evidence and unlocks hints. Unguided records
          &quot;unguided_lab&quot; evidence (independent demonstration) but has no hints available.
        </p>
        {error && <p className="mb-3 text-sm text-danger">{error}</p>}
        <div className="flex gap-3">
          <Button type="button" disabled={!!starting} onClick={() => startLab(true)}>
            {starting === "guided" ? "Starting..." : "Start guided"}
          </Button>
          <Button type="button" variant="secondary" disabled={!!starting} onClick={() => startLab(false)}>
            {starting === "unguided" ? "Starting..." : "Start unguided"}
          </Button>
        </div>
      </div>
    );
  }

  if (result?.correct || instance.status === "stopped") {
    return (
      <div className="rounded-lg border border-success/30 bg-success-muted p-5 text-sm text-success">
        Correct flag. Lab completed
        {instance.guided ? " (guided)" : " (unguided — independent demonstration recorded)"}.
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {instance.guided && hints.length > 0 && (
        <div className="rounded-lg border border-border bg-surface p-6">
          <h3 className="mb-3 text-sm font-semibold text-foreground">Hints</h3>
          <ul className="space-y-2">
            {hints
              .slice()
              .sort((a, b) => a.level - b.level)
              .map((hint) => (
                <li key={hint.id} className="rounded-md border border-border p-3 text-sm">
                  {unlockedContent[hint.id] !== undefined ? (
                    <p className="text-foreground">{unlockedContent[hint.id]}</p>
                  ) : (
                    <div className="flex items-center justify-between">
                      <span className="text-foreground-subtle">
                        Level {hint.level} hint ({hint.point_cost} pts)
                      </span>
                      <button
                        type="button"
                        disabled={unlockingId === hint.id}
                        onClick={() => unlockHint(hint.id)}
                        className="text-xs font-medium text-accent hover:underline disabled:opacity-50"
                      >
                        {unlockingId === hint.id ? "Unlocking..." : "Unlock"}
                      </button>
                    </div>
                  )}
                </li>
              ))}
          </ul>
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-3 text-sm font-semibold text-foreground">Submit flag</h3>
        <div className="flex gap-2">
          <Input value={flag} onChange={(e) => setFlag(e.target.value)} placeholder="ICOREPEN{...}" className="font-mono" />
          <Button type="button" disabled={submitting || !flag} onClick={submitFlag}>
            {submitting ? "Checking..." : "Submit"}
          </Button>
        </div>
        {result && !result.correct && <p className="mt-2 text-sm text-danger">Incorrect. Try again.</p>}
        {error && <p className="mt-2 text-sm text-danger">{error}</p>}
      </div>
    </div>
  );
}
