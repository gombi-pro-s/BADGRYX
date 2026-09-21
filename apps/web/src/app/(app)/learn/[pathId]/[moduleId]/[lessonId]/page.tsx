import Link from "next/link";
import { notFound } from "next/navigation";
import ReactMarkdown from "react-markdown";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { MarkRead } from "./mark-read";
import { QuizAttempt } from "./quiz-attempt";

interface QuizQuestion {
  question_id: string;
  question_text: string;
  question_type: string;
  choices: { choice_id: string; choice_text: string }[];
}

export default async function LessonPage({
  params,
}: {
  params: Promise<{ pathId: string; moduleId: string; lessonId: string }>;
}) {
  const { pathId, moduleId, lessonId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: lesson } = await supabase
    .from("lessons")
    .select("id, title, content_markdown, module_id")
    .eq("id", lessonId)
    .eq("published", true)
    .single();

  if (!lesson) notFound();

  const { data: linkedQuiz } = await supabase
    .from("quizzes")
    .select("id")
    .eq("lesson_id", lessonId)
    .eq("published", true)
    .maybeSingle();

  let quiz: { quizId: string; title: string; passingScore: number; questions: QuizQuestion[] } | null = null;

  if (linkedQuiz) {
    const { data: quizRows } = await supabase
      .from("quiz_questions_for_attempt")
      .select("quiz_id, title, passing_score, question_id, question_text, question_type, choice_id, choice_text")
      .eq("quiz_id", linkedQuiz.id);

    if (quizRows && quizRows.length > 0) {
      const questionsMap = new Map<string, QuizQuestion>();
      for (const row of quizRows) {
        if (!questionsMap.has(row.question_id)) {
          questionsMap.set(row.question_id, {
            question_id: row.question_id,
            question_text: row.question_text,
            question_type: row.question_type,
            choices: [],
          });
        }
        if (row.choice_id && row.choice_text) {
          questionsMap.get(row.question_id)!.choices.push({ choice_id: row.choice_id, choice_text: row.choice_text });
        }
      }
      quiz = {
        quizId: quizRows[0].quiz_id,
        title: quizRows[0].title,
        passingScore: quizRows[0].passing_score,
        questions: [...questionsMap.values()],
      };
    }
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <MarkRead userId={user.id} lessonId={lesson.id} />
      <Link
        href={`/learn/${pathId}/${moduleId}`}
        className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground"
      >
        &larr; Back
      </Link>
      <h1 className="mb-6 text-2xl font-semibold text-foreground">{lesson.title}</h1>
      <article className="prose prose-sm max-w-none text-foreground [&_a]:text-accent [&_code]:text-accent [&_h2]:mt-6 [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:mt-4 [&_h3]:font-semibold [&_p]:my-3 [&_pre]:overflow-x-auto [&_pre]:rounded-md [&_pre]:border [&_pre]:border-border [&_pre]:bg-background-subtle [&_pre]:p-3 [&_ul]:my-3 [&_ul]:list-disc [&_ul]:pl-6">
        <ReactMarkdown>{lesson.content_markdown}</ReactMarkdown>
      </article>

      {quiz && (
        <div className="mt-10 rounded-lg border border-border bg-surface p-6">
          <QuizAttempt
            quizId={quiz.quizId}
            title={quiz.title}
            passingScore={quiz.passingScore}
            questions={quiz.questions}
          />
        </div>
      )}
    </div>
  );
}
