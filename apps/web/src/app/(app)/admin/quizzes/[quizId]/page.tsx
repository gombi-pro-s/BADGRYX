import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../publish-toggle";
import { SkillTagger } from "../../skill-tagger";
import { setQuizSkillsAction, toggleQuizPublishedAction } from "../actions";
import { QuestionsManager } from "./questions-manager";

export default async function AdminQuizDetailPage({
  params,
}: {
  params: Promise<{ quizId: string }>;
}) {
  const { quizId } = await params;
  const supabase = await createClient();

  const [{ data: quiz }, { data: allSkills }, { data: quizSkills }, { data: questions }, { data: choices }] =
    await Promise.all([
      supabase.from("quizzes").select("id, slug, title, is_exam, published").eq("id", quizId).single(),
      supabase.from("skills").select("id, name").order("name"),
      supabase.from("quiz_skills").select("skill_id").eq("quiz_id", quizId),
      supabase.from("quiz_questions").select("id, question_text, question_type, order_index").eq("quiz_id", quizId).order("order_index"),
      supabase.from("quiz_choices").select("id, question_id, choice_text, is_correct, order_index"),
    ]);

  if (!quiz) notFound();

  const choicesByQuestion = new Map<string, typeof choices>();
  for (const choice of choices ?? []) {
    const list = choicesByQuestion.get(choice.question_id) ?? [];
    list.push(choice);
    choicesByQuestion.set(choice.question_id, list);
  }
  const questionsWithChoices = (questions ?? []).map((q) => ({
    ...q,
    choices: (choicesByQuestion.get(q.id) ?? []).sort((a, b) => a.order_index - b.order_index),
  }));

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{quiz.title}</h2>
        <PublishToggle published={quiz.published} onToggle={toggleQuizPublishedAction.bind(null, quiz.id)} />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Skills assessed</h3>
        <SkillTagger
          allSkills={allSkills ?? []}
          selectedSkillIds={(quizSkills ?? []).map((s) => s.skill_id)}
          onSave={(skillIds) => setQuizSkillsAction(quiz.id, skillIds)}
        />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Questions</h3>
        <QuestionsManager quizId={quiz.id} questions={questionsWithChoices} />
      </div>
    </div>
  );
}
