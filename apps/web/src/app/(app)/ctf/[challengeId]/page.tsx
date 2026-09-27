import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { FlagSubmit } from "./flag-submit";

export default async function CtfChallengePage({
  params,
}: {
  params: Promise<{ challengeId: string }>;
}) {
  const { challengeId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const { data: challenge } = await supabase
    .from("ctf_challenges_public")
    .select("id, title, description, category, difficulty, points")
    .eq("id", challengeId)
    .eq("published", true)
    .single();

  if (!challenge) notFound();

  const [{ data: solved }, { data: relatedInvestigations }] = await Promise.all([
    supabase
      .from("ctf_submissions")
      .select("id")
      .eq("challenge_id", challengeId)
      .eq("user_id", user.id)
      .eq("correct", true)
      .maybeSingle(),
    supabase.from("investigation_ctf_challenges").select("investigations(id, title)").eq("challenge_id", challengeId),
  ]);

  const relatedInvestigationItems = (relatedInvestigations ?? [])
    .map((r) => r.investigations as unknown as { id: string; title: string } | null)
    .filter((i): i is { id: string; title: string } => !!i);

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/ctf" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; All challenges
      </Link>
      <div className="mb-2 flex items-center gap-2 text-xs text-foreground-subtle">
        <span>{challenge.category}</span>
        <span>&middot;</span>
        <span>{challenge.difficulty}</span>
        <span>&middot;</span>
        <span>{challenge.points} pts</span>
      </div>
      <div className="mb-4 flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold text-foreground">{challenge.title}</h1>
        <Link
          href={`/mentor?contextType=ctf&contextId=${challenge.id}&mode=hint`}
          className="shrink-0 text-xs font-medium text-accent hover:underline"
        >
          Ask Mentor
        </Link>
      </div>
      {challenge.description && (
        <p className="mb-8 whitespace-pre-wrap text-sm text-foreground-muted">{challenge.description}</p>
      )}

      {relatedInvestigationItems.length > 0 && (
        <div className="mb-6 rounded-lg border border-border bg-background-subtle p-4">
          <p className="mb-2 text-xs font-semibold text-foreground-muted">
            Purple Team: a blue-team investigation analyzes this exact attack
          </p>
          <div className="flex flex-wrap gap-2">
            {relatedInvestigationItems.map((investigation) => (
              <Link
                key={investigation.id}
                href={`/investigate/${investigation.id}`}
                className="rounded-full border border-border px-2.5 py-0.5 text-xs text-accent hover:underline"
              >
                Blue team investigation: {investigation.title}
              </Link>
            ))}
          </div>
        </div>
      )}

      <FlagSubmit challengeId={challenge.id} initiallySolved={!!solved} />
    </div>
  );
}
