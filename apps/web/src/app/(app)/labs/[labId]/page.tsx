import Link from "next/link";
import { notFound } from "next/navigation";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { LabWorkspace } from "./lab-workspace";
import { Terminal } from "./terminal";

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
      .select("id, title, description, category, difficulty, estimated_minutes, points, has_terminal")
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

  const runningInstance = instances?.find((i) => i.status === "running") ?? null;
  let initialTranscript: { command: string; output: string }[] = [];
  if (lab.has_terminal && runningInstance) {
    const { data: transcript } = await supabase
      .from("lab_terminal_commands")
      .select("command, output")
      .eq("lab_instance_id", runningInstance.id)
      .order("created_at", { ascending: true });
    initialTranscript = transcript ?? [];
  }

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

      {!lab.has_terminal && (
        <div className="mb-6 rounded-md border border-warning/30 bg-warning-muted px-4 py-3 text-xs text-warning">
          This lab doesn&apos;t have an interactive terminal environment yet. Flag submission and
          scoring below are fully real and recorded to your Skill Graph.
        </div>
      )}

      <LabWorkspace
        labId={lab.id}
        userId={user.id}
        hints={hints ?? []}
        initialInstance={instances && instances.length > 0 ? instances[0] : null}
      />

      {lab.has_terminal && runningInstance && (
        <div className="mt-6">
          <h3 className="mb-3 text-sm font-semibold text-foreground">Terminal</h3>
          <Terminal labInstanceId={runningInstance.id} initialTranscript={initialTranscript} />
        </div>
      )}
    </div>
  );
}
