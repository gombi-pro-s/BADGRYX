"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";

interface Choice {
  choice_id: string;
  choice_text: string;
}
interface Question {
  question_id: string;
  question_text: string;
  question_type: string;
  choices: Choice[];
}

export function QuizAttempt({
  quizId,
  title,
  passingScore,
  questions,
}: {
  quizId: string;
  title: string;
  passingScore: number;
  questions: Question[];
}) {
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [result, setResult] = useState<{ passed: boolean; score: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit() {
    setPending(true);
    setError(null);
    const supabase = createClient();
    const payload: Record<string, string[]> = {};
    for (const q of questions) {
      payload[q.question_id] = answers[q.question_id] ? [answers[q.question_id]] : [];
    }
    const { data, error: rpcError } = await supabase.rpc("submit_quiz_attempt", {
      p_quiz_id: quizId,
      p_answers: payload,
    });
    setPending(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    const attempt = data as unknown as { passed: boolean; score: number };
    setResult({ passed: attempt.passed, score: attempt.score });
  }

  if (result) {
    return (
      <div
        className={`rounded-lg border p-5 ${
          result.passed ? "border-success/30 bg-success-muted" : "border-danger/30 bg-danger-muted"
        }`}
      >
        <p className={`text-sm font-semibold ${result.passed ? "text-success" : "text-danger"}`}>
          {result.passed ? "Passed" : "Not yet"} &mdash; {result.score}% (passing: {passingScore}%)
        </p>
        {!result.passed && (
          <button
            type="button"
            onClick={() => {
              setResult(null);
              setAnswers({});
            }}
            className="mt-2 text-xs font-medium text-accent hover:underline"
          >
            Try again
          </button>
        )}
      </div>
    );
  }

  return (
    <div>
      <h3 className="mb-4 text-sm font-semibold text-foreground">{title}</h3>
      <div className="space-y-5">
        {questions.map((q) => (
          <fieldset key={q.question_id}>
            <legend className="mb-2 text-sm text-foreground">{q.question_text}</legend>
            <div className="space-y-1.5">
              {q.choices.map((choice) => (
                <label key={choice.choice_id} className="flex items-center gap-2 text-sm text-foreground-muted">
                  <input
                    type="radio"
                    name={q.question_id}
                    value={choice.choice_id}
                    checked={answers[q.question_id] === choice.choice_id}
                    onChange={() => setAnswers((prev) => ({ ...prev, [q.question_id]: choice.choice_id }))}
                    className="h-4 w-4 border-border"
                  />
                  {choice.choice_text}
                </label>
              ))}
            </div>
          </fieldset>
        ))}
      </div>
      {error && <p className="mt-4 text-sm text-danger">{error}</p>}
      <Button type="button" className="mt-5" disabled={pending} onClick={submit}>
        {pending ? "Submitting..." : "Submit answers"}
      </Button>
    </div>
  );
}
