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

  const { data: solved } = await supabase
    .from("ctf_submissions")
    .select("id")
    .eq("challenge_id", challengeId)
    .eq("user_id", user.id)
    .eq("correct", true)
    .maybeSingle();

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
      <h1 className="mb-4 text-2xl font-semibold text-foreground">{challenge.title}</h1>
      {challenge.description && (
        <p className="mb-8 whitespace-pre-wrap text-sm text-foreground-muted">{challenge.description}</p>
      )}

      <FlagSubmit challengeId={challenge.id} initiallySolved={!!solved} />
    </div>
  );
}
