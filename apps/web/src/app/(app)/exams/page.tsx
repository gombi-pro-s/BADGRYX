import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Exams" };

export default async function ExamsPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: exams }, { data: attempts }] = await Promise.all([
    supabase
      .from("quizzes")
      .select("id, title, passing_score, max_attempts, time_limit_minutes")
      .eq("is_exam", true)
      .eq("published", true)
      .order("title"),
    supabase.from("quiz_attempts").select("quiz_id, passed").eq("user_id", user.id),
  ]);

  const passedByQuiz = new Set((attempts ?? []).filter((a) => a.passed).map((a) => a.quiz_id));
  const attemptCountByQuiz = new Map<string, number>();
  for (const a of attempts ?? []) {
    attemptCountByQuiz.set(a.quiz_id, (attemptCountByQuiz.get(a.quiz_id) ?? 0) + 1);
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Exams</h1>
      <p className="mb-8 text-sm text-foreground-muted">
        Timed, real assessments -- graded the same way as every quiz here, server-side against a hidden answer
        key. A passed exam records &quot;assessment&quot; evidence in your Skill Graph, the same weight as a
        formal skills assessment.
      </p>

      {exams && exams.length > 0 ? (
        <ul className="divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {exams.map((exam) => {
            const passed = passedByQuiz.has(exam.id);
            const used = attemptCountByQuiz.get(exam.id) ?? 0;
            return (
              <li key={exam.id}>
                <Link
                  href={`/exams/${exam.id}`}
                  className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-background-subtle"
                >
                  <div>
                    <p className="text-sm font-medium text-foreground">{exam.title}</p>
                    <p className="mt-0.5 text-xs text-foreground-subtle">
                      Pass at {exam.passing_score}%
                      {exam.time_limit_minutes !== null && <> &middot; {exam.time_limit_minutes} min</>}
                      {exam.max_attempts !== null && <> &middot; {used}/{exam.max_attempts} attempts used</>}
                    </p>
                  </div>
                  {passed && (
                    <span className="shrink-0 rounded-full bg-success-muted px-2.5 py-0.5 text-xs font-medium text-success">
                      Passed
                    </span>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      ) : (
        <div className="rounded-lg border border-dashed border-border bg-surface p-8 text-center text-sm text-foreground-muted">
          No exams published yet.
        </div>
      )}
    </div>
  );
}
