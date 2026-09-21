"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export function FlagSubmit({
  challengeId,
  initiallySolved,
}: {
  challengeId: string;
  initiallySolved: boolean;
}) {
  const [flag, setFlag] = useState("");
  const [pending, setPending] = useState(false);
  const [result, setResult] = useState<{ correct: boolean; points: number } | null>(
    initiallySolved ? { correct: true, points: 0 } : null,
  );
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setPending(true);
    setError(null);
    const supabase = createClient();
    const { data, error: rpcError } = await supabase.rpc("submit_ctf_flag", {
      p_challenge_id: challengeId,
      p_flag: flag,
    });
    setPending(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    const submission = data as unknown as { correct: boolean; points_awarded: number };
    setResult({ correct: submission.correct, points: submission.points_awarded });
    if (!submission.correct) setFlag("");
  }

  if (result?.correct) {
    return (
      <div className="rounded-lg border border-success/30 bg-success-muted p-4 text-sm text-success">
        Correct{result.points > 0 ? ` — +${result.points} points` : ""}. This skill&apos;s evidence has
        been recorded.
      </div>
    );
  }

  return (
    <div>
      <div className="flex gap-2">
        <Input
          value={flag}
          onChange={(e) => setFlag(e.target.value)}
          placeholder="ICOREPEN{...}"
          className="font-mono"
        />
        <Button type="button" disabled={pending || !flag} onClick={submit}>
          {pending ? "Checking..." : "Submit"}
        </Button>
      </div>
      {result && !result.correct && <p className="mt-2 text-sm text-danger">Incorrect. Try again.</p>}
      {error && <p className="mt-2 text-sm text-danger">{error}</p>}
    </div>
  );
}
