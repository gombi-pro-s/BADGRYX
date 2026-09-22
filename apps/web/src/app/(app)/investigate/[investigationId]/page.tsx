import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { NotesPad } from "./notes-pad";
import { InvestigationAnswers } from "./investigation-answers";
import type { InvestigationQuestionType } from "@/types/database";

interface Question {
  question_id: string;
  question_text: string;
  question_type: InvestigationQuestionType;
  choices: { choice_id: string; choice_text: string }[];
}

const ARTIFACT_TYPE_LABELS: Record<string, string> = {
  whois_record: "WHOIS record",
  email_headers: "Email headers",
  social_media_profile: "Social media profile",
  file_metadata: "File metadata",
  log_excerpt: "Log excerpt",
  network_capture_summary: "Network capture summary",
  document_excerpt: "Document excerpt",
  chat_transcript: "Chat transcript",
};

export default async function InvestigationDetailPage({
  params,
}: {
  params: Promise<{ investigationId: string }>;
}) {
  const { investigationId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: investigation }, { data: skillLinks }, { data: artifacts }, { data: questionRows }, { data: instance }] =
    await Promise.all([
      supabase
        .from("investigations")
        .select("id, title, briefing, category, difficulty, estimated_minutes, points, passing_score")
        .eq("id", investigationId)
        .eq("published", true)
        .single(),
      supabase.from("investigation_skills").select("skills(name)").eq("investigation_id", investigationId),
      supabase
        .from("investigation_artifacts")
        .select("id, artifact_type, title, content")
        .eq("investigation_id", investigationId)
        .order("order_index"),
      supabase
        .from("investigation_questions_for_attempt")
        .select("question_id, question_text, question_type, choice_id, choice_text")
        .eq("investigation_id", investigationId),
      supabase
        .from("investigation_instances")
        .select("notes")
        .eq("investigation_id", investigationId)
        .eq("user_id", user.id)
        .maybeSingle(),
    ]);

  if (!investigation) notFound();

  const skillNames = (skillLinks ?? [])
    .map((s) => (s.skills as unknown as { name: string } | null)?.name)
    .filter((n): n is string => !!n);

  const questionsMap = new Map<string, Question>();
  for (const row of questionRows ?? []) {
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
  const questions = [...questionsMap.values()];

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <Link href="/investigate" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; All investigations
      </Link>

      <div className="mb-2 flex items-center gap-2 text-xs text-foreground-subtle">
        <span>{investigation.category}</span>
        <span>&middot;</span>
        <span>{investigation.difficulty}</span>
        <span>&middot;</span>
        <span>{investigation.estimated_minutes} min</span>
        <span>&middot;</span>
        <span>{investigation.points} pts</span>
      </div>
      <div className="mb-3 flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold text-foreground">{investigation.title}</h1>
        <Link
          href={`/mentor?contextType=investigation&contextId=${investigation.id}`}
          className="shrink-0 text-xs font-medium text-accent hover:underline"
        >
          Ask Mentor
        </Link>
      </div>
      {skillNames.length > 0 && (
        <div className="mb-4 flex flex-wrap gap-1.5">
          {skillNames.map((name) => (
            <span key={name} className="rounded-full border border-border px-2.5 py-0.5 text-xs text-foreground-muted">
              {name}
            </span>
          ))}
        </div>
      )}
      {investigation.briefing && (
        <p className="mb-8 whitespace-pre-wrap text-sm text-foreground-muted">{investigation.briefing}</p>
      )}

      <h2 className="mb-3 text-sm font-semibold text-foreground">Evidence</h2>
      <div className="mb-8 space-y-3">
        {(artifacts ?? []).map((artifact) => (
          <details key={artifact.id} className="rounded-lg border border-border bg-surface p-4" open>
            <summary className="cursor-pointer text-sm font-medium text-foreground">
              <span className="mr-2 text-xs font-normal text-foreground-subtle uppercase">
                {ARTIFACT_TYPE_LABELS[artifact.artifact_type] ?? artifact.artifact_type}
              </span>
              {artifact.title}
            </summary>
            <pre className="mt-3 overflow-x-auto rounded-md bg-background-subtle p-3 font-mono text-xs whitespace-pre-wrap text-foreground">
              {artifact.content}
            </pre>
          </details>
        ))}
      </div>

      <div className="mb-8">
        <NotesPad investigationId={investigation.id} userId={user.id} initialNotes={instance?.notes ?? ""} />
      </div>

      {questions.length > 0 && (
        <InvestigationAnswers investigationId={investigation.id} passingScore={investigation.passing_score} questions={questions} />
      )}
    </div>
  );
}
