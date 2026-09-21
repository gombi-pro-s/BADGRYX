import type { Metadata } from "next";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CreateQuizForm } from "./create-quiz-form";

export const metadata: Metadata = { title: "Quizzes" };

export default async function AdminQuizzesPage() {
  const supabase = await createClient();
  const { data: quizzes } = await supabase
    .from("quizzes")
    .select("id, slug, title, is_exam, published")
    .order("title");

  return (
    <div>
      <h2 className="mb-4 text-lg font-semibold text-foreground">Quizzes</h2>

      {quizzes && quizzes.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {quizzes.map((q) => (
            <li key={q.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <div className="min-w-0">
                <Link href={`/admin/quizzes/${q.id}`} className="text-sm font-medium text-foreground hover:underline">
                  {q.title}
                </Link>
                {q.is_exam && <span className="ml-2 text-xs text-accent">Exam</span>}
              </div>
              <span
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                  q.published ? "bg-success-muted text-success" : "bg-background-subtle text-foreground-subtle"
                }`}
              >
                {q.published ? "Published" : "Draft"}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No quizzes yet. Create the first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">New quiz</h3>
        <CreateQuizForm />
      </div>
    </div>
  );
}
