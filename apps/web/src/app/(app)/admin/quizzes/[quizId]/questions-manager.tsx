"use client";

import { useState, useTransition } from "react";
import { createQuestionAction, deleteQuestionAction, type ChoiceInput } from "../actions";
import { Button } from "@/components/ui/button";
import { Input, Label } from "@/components/ui/input";

interface Choice {
  id: string;
  choice_text: string;
  is_correct: boolean;
}

interface Question {
  id: string;
  question_text: string;
  question_type: string;
  choices: Choice[];
}

const EMPTY_CHOICES: ChoiceInput[] = [
  { text: "", isCorrect: false },
  { text: "", isCorrect: false },
];

export function QuestionsManager({ quizId, questions }: { quizId: string; questions: Question[] }) {
  const [questionText, setQuestionText] = useState("");
  const [choices, setChoices] = useState<ChoiceInput[]>(EMPTY_CHOICES);
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
        await createQuestionAction(quizId, questionText, "single_choice", choices);
        setQuestionText("");
        setChoices(EMPTY_CHOICES);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to create question.");
      }
    });
  }

  return (
    <div>
      {questions.length > 0 ? (
        <ul className="mb-6 space-y-3">
          {questions.map((q) => (
            <li key={q.id} className="rounded-md border border-border p-3">
              <div className="flex items-start justify-between gap-3">
                <p className="text-sm font-medium text-foreground">{q.question_text}</p>
                <button
                  type="button"
                  disabled={deletePending}
                  onClick={() => startDelete(() => deleteQuestionAction(quizId, q.id))}
                  className="shrink-0 text-xs text-danger hover:underline disabled:opacity-50"
                >
                  Remove
                </button>
              </div>
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
            </li>
          ))}
        </ul>
      ) : (
        <p className="mb-6 text-sm text-foreground-muted">No questions yet. The quiz cannot be graded without one.</p>
      )}

      <div className="space-y-3 rounded-md border border-dashed border-border p-3">
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
              <Input
                value={choice.text}
                onChange={(e) => updateChoice(i, { text: e.target.value })}
                placeholder={`Choice ${i + 1}`}
              />
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
        {error && <p className="text-sm text-danger">{error}</p>}
        <Button type="button" size="sm" disabled={pending} onClick={submit}>
          {pending ? "Adding..." : "Add question"}
        </Button>
      </div>
    </div>
  );
}
