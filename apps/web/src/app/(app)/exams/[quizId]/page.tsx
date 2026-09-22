import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { ExamAttempt } from "./exam-attempt";
import type { QuestionType } from "@/types/database";

interface QuestionRow {
  question_id: string;
  question_text: string;
  question_type: QuestionType;
  order_index: number;
  points: number;
  choice_id: string | null;
  choice_text: string | null;
  choice_order_index: number | null;
}

export default async function ExamDetailPage({ params }: { params: Promise<{ quizId: string }> }) {
  const { quizId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: rows }, { data: priorAttempts }] = await Promise.all([
    supabase
      .from("quiz_questions_for_attempt")
      .select(
        "quiz_id, title, passing_score, max_attempts, is_exam, time_limit_minutes, hint_policy, question_id, question_text, question_type, order_index, points, choice_id, choice_text, choice_order_index",
      )
      .eq("quiz_id", quizId)
      .order("order_index")
      .order("choice_order_index"),
    supabase
      .from("quiz_attempts")
      .select("score, passed, submitted_at")
      .eq("quiz_id", quizId)
      .eq("user_id", user.id)
      .order("submitted_at", { ascending: false }),
  ]);

  if (!rows || rows.length === 0 || !rows[0].is_exam) notFound();

  const meta = rows[0];
  const questionsById = new Map<string, QuestionRow & { choices: { choice_id: string; choice_text: string }[] }>();
  for (const row of rows) {
    let q = questionsById.get(row.question_id);
    if (!q) {
      q = { ...row, choices: [] };
      questionsById.set(row.question_id, q);
    }
    if (row.choice_id && row.choice_text) {
      q.choices.push({ choice_id: row.choice_id, choice_text: row.choice_text });
    }
  }
  const questions = [...questionsById.values()].sort((a, b) => a.order_index - b.order_index);

  const attemptsUsed = priorAttempts?.length ?? 0;
  const alreadyPassed = (priorAttempts ?? []).some((a) => a.passed);
  const attemptsRemaining =
    meta.max_attempts !== null ? Math.max(0, meta.max_attempts - attemptsUsed) : null;

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/exams" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; All exams
      </Link>
      <h1 className="mb-2 text-2xl font-semibold text-foreground">{meta.title}</h1>
      <p className="mb-6 text-sm text-foreground-muted">
        Passing score: {meta.passing_score}%
        {meta.max_attempts !== null && <> &middot; {meta.max_attempts} attempt{meta.max_attempts === 1 ? "" : "s"} allowed</>}
        {meta.time_limit_minutes !== null && <> &middot; {meta.time_limit_minutes} minute time limit</>}
      </p>

      {priorAttempts && priorAttempts.length > 0 && (
        <div className="mb-6 rounded-lg border border-border bg-surface p-4">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-foreground-subtle">
            Your previous attempts
          </h2>
          <ul className="space-y-1">
            {priorAttempts.map((a, i) => (
              <li key={i} className="flex items-center justify-between text-sm">
                <span className="text-foreground-subtle">{new Date(a.submitted_at).toLocaleDateString()}</span>
                <span className={a.passed ? "text-success" : "text-danger"}>
                  {a.score}% &mdash; {a.passed ? "Passed" : "Failed"}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {alreadyPassed ? (
        <div className="rounded-lg border border-success/30 bg-success-muted p-4 text-sm text-success">
          You&apos;ve already passed this exam.
        </div>
      ) : (
        <ExamAttempt
          quizId={meta.quiz_id}
          title={meta.title}
          passingScore={meta.passing_score}
          timeLimitMinutes={meta.time_limit_minutes}
          hintPolicy={meta.hint_policy}
          questions={questions}
          attemptsRemaining={attemptsRemaining}
        />
      )}
    </div>
  );
}
