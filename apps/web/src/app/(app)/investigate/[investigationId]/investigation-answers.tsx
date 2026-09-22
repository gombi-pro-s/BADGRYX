"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { InvestigationQuestionType } from "@/types/database";

interface Choice {
  choice_id: string;
  choice_text: string;
}
interface Question {
  question_id: string;
  question_text: string;
  question_type: InvestigationQuestionType;
  choices: Choice[];
}

export function InvestigationAnswers({
  investigationId,
  passingScore,
  questions,
}: {
  investigationId: string;
  passingScore: number;
  questions: Question[];
}) {
  const [choiceAnswers, setChoiceAnswers] = useState<Record<string, string>>({});
  const [textAnswers, setTextAnswers] = useState<Record<string, string>>({});
  const [result, setResult] = useState<{ passed: boolean; score: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit() {
    setPending(true);
    setError(null);
    const supabase = createClient();
    const payload: Record<string, string[] | string> = {};
    for (const q of questions) {
      payload[q.question_id] =
        q.question_type === "multiple_choice" ? (choiceAnswers[q.question_id] ? [choiceAnswers[q.question_id]] : []) : (textAnswers[q.question_id] ?? "");
    }
    const { data, error: rpcError } = await supabase.rpc("submit_investigation_answers", {
      p_investigation_id: investigationId,
      p_answers: payload,
    });
    setPending(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    setResult({ passed: data.passed, score: data.score });
  }

  if (result) {
    return (
      <div
        className={`rounded-lg border p-5 ${
          result.passed ? "border-success/30 bg-success-muted" : "border-danger/30 bg-danger-muted"
        }`}
      >
        <p className={`text-sm font-semibold ${result.passed ? "text-success" : "text-danger"}`}>
          {result.passed ? "Case solved" : "Not yet"} &mdash; {result.score}% (passing: {passingScore}%)
        </p>
        {!result.passed && (
          <button
            type="button"
            onClick={() => setResult(null)}
            className="mt-2 text-xs font-medium text-accent hover:underline"
          >
            Review the evidence again and retry
          </button>
        )}
      </div>
    );
  }

  return (
    <div className="rounded-lg border border-border bg-surface p-6">
      <h3 className="mb-4 text-sm font-semibold text-foreground">Your findings</h3>
      <div className="space-y-5">
        {questions.map((q) => (
          <fieldset key={q.question_id}>
            <legend className="mb-2 text-sm text-foreground">{q.question_text}</legend>
            {q.question_type === "multiple_choice" ? (
              <div className="space-y-1.5">
                {q.choices.map((choice) => (
                  <label key={choice.choice_id} className="flex items-center gap-2 text-sm text-foreground-muted">
                    <input
                      type="radio"
                      name={q.question_id}
                      value={choice.choice_id}
                      checked={choiceAnswers[q.question_id] === choice.choice_id}
                      onChange={() => setChoiceAnswers((prev) => ({ ...prev, [q.question_id]: choice.choice_id }))}
                      className="h-4 w-4 border-border"
                    />
                    {choice.choice_text}
                  </label>
                ))}
              </div>
            ) : (
              <Input
                value={textAnswers[q.question_id] ?? ""}
                onChange={(e) => setTextAnswers((prev) => ({ ...prev, [q.question_id]: e.target.value }))}
                placeholder="Your answer"
                autoComplete="off"
              />
            )}
          </fieldset>
        ))}
      </div>
      {error && <p className="mt-4 text-sm text-danger">{error}</p>}
      <Button type="button" className="mt-5" disabled={pending} onClick={submit}>
        {pending ? "Submitting..." : "Submit findings"}
      </Button>
    </div>
  );
}
