"use client";

import { useState, useTransition } from "react";
import {
  createExactTextQuestionAction,
  createMultipleChoiceQuestionAction,
  deleteQuestionAction,
  type ChoiceInput,
} from "../actions";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";
import type { InvestigationQuestionType } from "@/types/database";

interface Choice {
  id: string;
  choice_text: string;
  is_correct: boolean;
}

interface Question {
  id: string;
  question_text: string;
  question_type: InvestigationQuestionType;
  points: number;
  choices: Choice[];
}

const EMPTY_CHOICES: ChoiceInput[] = [
  { text: "", isCorrect: false },
  { text: "", isCorrect: false },
];

export function QuestionsManager({ investigationId, questions }: { investigationId: string; questions: Question[] }) {
  const [questionType, setQuestionType] = useState<InvestigationQuestionType>("multiple_choice");
  const [questionText, setQuestionText] = useState("");
  const [points, setPoints] = useState(1);
  const [choices, setChoices] = useState<ChoiceInput[]>(EMPTY_CHOICES);
  const [exactAnswer, setExactAnswer] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const [deletePending, startDelete] = useTransition();

  function updateChoice(index: number, patch: Partial<ChoiceInput>) {
    setChoices((prev) => prev.map((c, i) => (i === index ? { ...c, ...patch } : c)));
  }

  function submit() {
    setError(null);
    startTransition(async () => {
      try {
        if (questionType === "multiple_choice") {
          await createMultipleChoiceQuestionAction(investigationId, questionText, points, choices);
          setChoices(EMPTY_CHOICES);
        } else {
          await createExactTextQuestionAction(investigationId, questionText, points, exactAnswer);
          setExactAnswer("");
        }
        setQuestionText("");
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to create question.");
      }
    });
  }

  return (
    <div>
      <p className="mb-3 text-xs text-foreground-subtle">
        exact_text answers are hashed the moment you submit this form -- the plaintext is never stored or shown
        again after creation, same discipline as lab/CTF flags.
      </p>

      {questions.length > 0 ? (
        <ul className="mb-6 space-y-3">
          {questions.map((q) => (
            <li key={q.id} className="rounded-md border border-border p-3">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-sm font-medium text-foreground">{q.question_text}</p>
                  <p className="text-xs text-foreground-subtle">
                    {q.question_type} &middot; {q.points} pt{q.points === 1 ? "" : "s"}
                  </p>
                </div>
                <button
                  type="button"
                  disabled={deletePending}
                  onClick={() => startDelete(() => deleteQuestionAction(investigationId, q.id))}
                  className="shrink-0 text-xs text-danger hover:underline disabled:opacity-50"
                >
                  Remove
                </button>
              </div>
              {q.question_type === "multiple_choice" && (
                <ul className="mt-2 space-y-1">
                  {q.choices.map((c) => (
                    <li key={c.id} className="flex items-center gap-2 text-xs">
                      <span className={c.is_correct ? "text-success" : "text-foreground-subtle"}>
                        {c.is_correct ? "✓" : "○"}
                      </span>
                      <span className="text-foreground-muted">{c.choice_text}</span>
                    </li>
                  ))}
                </ul>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mb-6 text-sm text-foreground-muted">No questions yet. The investigation cannot be graded without one.</p>
      )}

      <div className="space-y-3 rounded-md border border-dashed border-border p-3">
        <div className="flex gap-1.5">
          {(["multiple_choice", "exact_text"] as InvestigationQuestionType[]).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setQuestionType(t)}
              className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${
                questionType === t ? "bg-accent-muted text-accent" : "text-foreground-muted hover:bg-background-subtle"
              }`}
            >
              {t === "multiple_choice" ? "Multiple choice" : "Exact text"}
            </button>
          ))}
        </div>

        <div>
          <Label htmlFor="question_text">Question</Label>
          <textarea
            id="question_text"
            value={questionText}
            onChange={(e) => setQuestionText(e.target.value)}
            rows={2}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>

        <div className="w-24">
          <Label htmlFor="points">Points</Label>
          <Input id="points" type="number" min={1} max={100} value={points} onChange={(e) => setPoints(Number(e.target.value))} />
        </div>

        {questionType === "multiple_choice" ? (
          <div className="space-y-2">
            <Label>Choices (check the correct one(s))</Label>
            {choices.map((choice, i) => (
              <div key={i} className="flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={choice.isCorrect}
                  onChange={(e) => updateChoice(i, { isCorrect: e.target.checked })}
                  className="h-4 w-4 rounded border-border"
                  aria-label={`Choice ${i + 1} is correct`}
                />
                <Input value={choice.text} onChange={(e) => updateChoice(i, { text: e.target.value })} placeholder={`Choice ${i + 1}`} />
              </div>
            ))}
            <button
              type="button"
              onClick={() => setChoices((prev) => [...prev, { text: "", isCorrect: false }])}
              className="text-xs font-medium text-accent hover:underline"
            >
              + Add choice
            </button>
          </div>
        ) : (
          <div>
            <Label htmlFor="exact_answer">Correct answer (hashed on submit, normalized case/whitespace-insensitive)</Label>
            <Input id="exact_answer" value={exactAnswer} onChange={(e) => setExactAnswer(e.target.value)} autoComplete="off" />
          </div>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}
        <Button type="button" size="sm" disabled={pending} onClick={submit}>
          {pending ? "Adding..." : "Add question"}
        </Button>
      </div>
    </div>
  );
}
