import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { LabWorkspace } from "./lab-workspace";

export default async function LabDetailPage({
  params,
}: {
  params: Promise<{ labId: string }>;
}) {
  const { labId } = await params;
  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: lab }, { data: skillLinks }, { data: hints }, { data: instances }] = await Promise.all([
    supabase
      .from("labs")
      .select("id, title, description, category, difficulty, estimated_minutes, points")
      .eq("id", labId)
      .eq("published", true)
      .single(),
    supabase.from("lab_skills").select("skills(name)").eq("lab_id", labId),
    supabase.from("lab_hints").select("id, level, point_cost").eq("lab_id", labId),
    supabase
      .from("lab_instances")
      .select("id, guided, status")
      .eq("lab_id", labId)
      .eq("user_id", user.id)
      .order("started_at", { ascending: false })
      .limit(1),
  ]);

  if (!lab) notFound();

  const skillNames = (skillLinks ?? [])
    .map((s) => (s.skills as unknown as { name: string } | null)?.name)
    .filter((n): n is string => !!n);

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/labs" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; All labs
      </Link>
      <div className="mb-2 flex items-center gap-2 text-xs text-foreground-subtle">
        <span>{lab.category}</span>
        <span>&middot;</span>
        <span>{lab.difficulty}</span>
        <span>&middot;</span>
        <span>{lab.estimated_minutes} min</span>
        <span>&middot;</span>
        <span>{lab.points} pts</span>
      </div>
      <div className="mb-3 flex items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold text-foreground">{lab.title}</h1>
        <Link
          href={`/mentor?contextType=lab&contextId=${lab.id}`}
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
      {lab.description && (
        <p className="mb-6 whitespace-pre-wrap text-sm text-foreground-muted">{lab.description}</p>
      )}

      <div className="mb-6 rounded-md border border-warning/30 bg-warning-muted px-4 py-3 text-xs text-warning">
        The sandboxed target environment for this lab isn&apos;t provisioned automatically yet (lab
        engine build in progress). Flag submission and scoring below are fully real and recorded to
        your Skill Graph.
      </div>

      <LabWorkspace
        labId={lab.id}
        userId={user.id}
        hints={hints ?? []}
        initialInstance={instances && instances.length > 0 ? instances[0] : null}
      />
    </div>
  );
}
