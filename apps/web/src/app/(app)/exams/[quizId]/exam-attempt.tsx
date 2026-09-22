"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import type { HintPolicy, QuestionType } from "@/types/database";

interface Choice {
  choice_id: string;
  choice_text: string;
}
interface Question {
  question_id: string;
  question_text: string;
  question_type: QuestionType;
  points: number;
  choices: Choice[];
}

const HINT_POLICY_COPY: Record<HintPolicy, string> = {
  none: "No hints -- exam conditions. Answer from what you know.",
  limited: "Limited hints are available for this exam.",
  full: "Full hints are available for this exam.",
};

function formatTime(totalSeconds: number) {
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export function ExamAttempt({
  quizId,
  title,
  passingScore,
  timeLimitMinutes,
  hintPolicy,
  questions,
  attemptsRemaining,
}: {
  quizId: string;
  title: string;
  passingScore: number;
  timeLimitMinutes: number | null;
  hintPolicy: HintPolicy;
  questions: Question[];
  attemptsRemaining: number | null;
}) {
  const [answers, setAnswers] = useState<Record<string, string[]>>({});
  const [result, setResult] = useState<{ passed: boolean; score: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [secondsLeft, setSecondsLeft] = useState<number | null>(timeLimitMinutes ? timeLimitMinutes * 60 : null);
  const submittingRef = useRef(false);

  function toggleSingle(questionId: string, choiceId: string) {
    setAnswers((prev) => ({ ...prev, [questionId]: [choiceId] }));
  }

  function toggleMulti(questionId: string, choiceId: string) {
    setAnswers((prev) => {
      const current = prev[questionId] ?? [];
      const next = current.includes(choiceId) ? current.filter((c) => c !== choiceId) : [...current, choiceId];
      return { ...prev, [questionId]: next };
    });
  }

  async function submit() {
    if (submittingRef.current) return;
    submittingRef.current = true;
    setPending(true);
    setError(null);
    const supabase = createClient();
    const payload: Record<string, string[]> = {};
    for (const q of questions) {
      payload[q.question_id] = answers[q.question_id] ?? [];
    }
    const { data, error: rpcError } = await supabase.rpc("submit_quiz_attempt", {
      p_quiz_id: quizId,
      p_answers: payload,
    });
    setPending(false);
    if (rpcError) {
      setError(rpcError.message);
      submittingRef.current = false;
      return;
    }
    const attempt = data as unknown as { passed: boolean; score: number };
    setResult({ passed: attempt.passed, score: attempt.score });
  }

  // Countdown timer -- client-side only, starting the moment this page is
  // rendered. There is no server-side exam-session record (unlike
  // lab_instances/investigation_instances), so a page refresh restarts the
  // clock; this is an honest, documented limitation, not enforced timing.
  useEffect(() => {
    if (secondsLeft === null || result) return;
    if (secondsLeft <= 0) {
      // Deferred out of the effect's synchronous body -- submit() calls
      // setState, which react-hooks/set-state-in-effect (rightly) flags if
      // called directly during the effect's own execution.
      const expiry = setTimeout(() => submit(), 0);
      return () => clearTimeout(expiry);
    }
    const timer = setTimeout(() => setSecondsLeft((s) => (s === null ? null : s - 1)), 1000);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [secondsLeft, result]);

  useEffect(() => {
    if (result || secondsLeft === null) return;
    function warn(e: BeforeUnloadEvent) {
      e.preventDefault();
    }
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [result, secondsLeft]);

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
      </div>
    );
  }

  if (attemptsRemaining !== null && attemptsRemaining <= 0) {
    return (
      <div className="rounded-lg border border-border bg-surface p-5 text-sm text-foreground-muted">
        You&apos;ve used all your attempts for this exam.
      </div>
    );
  }

  return (
    <div>
      <div className="mb-5 flex items-center justify-between gap-4 rounded-lg border border-border bg-surface p-4">
        <div>
          <h3 className="text-sm font-semibold text-foreground">{title}</h3>
          <p className="mt-1 text-xs text-foreground-subtle">{HINT_POLICY_COPY[hintPolicy]}</p>
        </div>
        {secondsLeft !== null && (
          <span
            className={`shrink-0 rounded-md border px-3 py-1.5 font-mono text-sm font-semibold ${
              secondsLeft <= 60
                ? "border-danger/30 bg-danger-muted text-danger"
                : "border-border bg-background-subtle text-foreground"
            }`}
          >
            {formatTime(secondsLeft)}
          </span>
        )}
      </div>

      <div className="space-y-5">
        {questions.map((q) => (
          <fieldset key={q.question_id}>
            <legend className="mb-2 text-sm text-foreground">
              {q.question_text}{" "}
              <span className="text-xs text-foreground-subtle">
                ({q.points} {q.points === 1 ? "point" : "points"})
              </span>
            </legend>
            {q.question_type === "short_answer" ? (
              <p className="text-xs text-foreground-subtle">This question type isn&apos;t auto-gradable yet.</p>
            ) : (
              <div className="space-y-1.5">
                {q.choices.map((choice) => (
                  <label key={choice.choice_id} className="flex items-center gap-2 text-sm text-foreground-muted">
                    <input
                      type={q.question_type === "multi_choice" ? "checkbox" : "radio"}
                      name={q.question_type === "multi_choice" ? undefined : q.question_id}
                      checked={(answers[q.question_id] ?? []).includes(choice.choice_id)}
                      onChange={() =>
                        q.question_type === "multi_choice"
                          ? toggleMulti(q.question_id, choice.choice_id)
                          : toggleSingle(q.question_id, choice.choice_id)
                      }
                      className="h-4 w-4 border-border"
                    />
                    {choice.choice_text}
                  </label>
                ))}
              </div>
            )}
          </fieldset>
        ))}
      </div>
      {error && <p className="mt-4 text-sm text-danger">{error}</p>}
      <Button type="button" className="mt-5" disabled={pending} onClick={submit}>
        {pending ? "Submitting..." : "Submit exam"}
      </Button>
    </div>
  );
}
