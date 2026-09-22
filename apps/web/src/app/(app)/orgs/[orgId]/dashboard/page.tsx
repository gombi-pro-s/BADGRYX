import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { requireOrgInstructor } from "@/lib/auth/org";
import { createClient } from "@/lib/supabase/server";
import type { SkillState } from "@/types/database";

export const metadata: Metadata = { title: "Instructor dashboard" };

interface MemberStats {
  userId: string;
  name: string;
  role: string;
  masteredOrDemonstrated: number;
  inProgress: number;
  labsCompleted: number;
  quizzesPassed: number;
  ctfSolved: number;
  investigationsPassed: number;
}

const PROVEN_STATES: SkillState[] = ["DEMONSTRATED", "MASTERED"];
const IN_PROGRESS_STATES: SkillState[] = ["LEARNING", "PRACTICING", "ASSESSED"];

export default async function InstructorDashboardPage({ params }: { params: Promise<{ orgId: string }> }) {
  const { orgId } = await params;
  await requireOrgInstructor(orgId);
  const supabase = await createClient();

  const { data: organization } = await supabase.from("organizations").select("*").eq("id", orgId).maybeSingle();
  if (!organization) notFound();

  const { data: members } = await supabase
    .from("organization_members")
    .select("user_id, role")
    .eq("organization_id", orgId)
    .order("joined_at");

  const memberIds = (members ?? []).map((m) => m.user_id);

  if (memberIds.length === 0) {
    return (
      <div className="mx-auto max-w-5xl px-6 py-10">
        <DashboardHeader organization={organization} />
        <div className="rounded-lg border border-dashed border-border bg-surface p-6 text-center text-sm text-foreground-muted">
          No members yet.
        </div>
      </div>
    );
  }

  // Every one of these queries is RLS-scoped to the caller's own session --
  // this instructor sees exactly these members' rows because they're an
  // instructor/team_owner/org_admin of this org, not because of a bypass.
  // See 20260922000012_org_instructor_visibility_and_invitations.sql.
  const [{ data: profiles }, { data: states }, { data: labProgress }, { data: quizAttempts }, { data: ctfSubs }, { data: investigationSubs }] =
    await Promise.all([
      supabase.from("profiles").select("id, display_name, username").in("id", memberIds),
      supabase.from("user_skill_states").select("user_id, state").in("user_id", memberIds),
      supabase.from("lab_progress").select("user_id, status").in("user_id", memberIds),
      supabase.from("quiz_attempts").select("user_id, passed").in("user_id", memberIds),
      supabase.from("ctf_submissions").select("user_id, correct").in("user_id", memberIds),
      supabase.from("investigation_submissions").select("user_id, passed").in("user_id", memberIds),
    ]);

  const profileById = new Map((profiles ?? []).map((p) => [p.id, p]));

  const stats: MemberStats[] = (members ?? []).map((m) => {
    const profile = profileById.get(m.user_id);
    const myStates = (states ?? []).filter((s) => s.user_id === m.user_id);
    return {
      userId: m.user_id,
      name: profile?.display_name ?? profile?.username ?? m.user_id,
      role: m.role,
      masteredOrDemonstrated: myStates.filter((s) => PROVEN_STATES.includes(s.state)).length,
      inProgress: myStates.filter((s) => IN_PROGRESS_STATES.includes(s.state)).length,
      labsCompleted: (labProgress ?? []).filter((l) => l.user_id === m.user_id && l.status === "completed").length,
      quizzesPassed: (quizAttempts ?? []).filter((q) => q.user_id === m.user_id && q.passed).length,
      ctfSolved: (ctfSubs ?? []).filter((c) => c.user_id === m.user_id && c.correct).length,
      investigationsPassed: (investigationSubs ?? []).filter((i) => i.user_id === m.user_id && i.passed).length,
    };
  });

  return (
    <div className="mx-auto max-w-5xl px-6 py-10">
      <DashboardHeader organization={organization} />

      <div className="overflow-x-auto rounded-lg border border-border bg-surface">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-foreground-subtle">
              <th className="px-4 py-3">Member</th>
              <th className="px-4 py-3">Role</th>
              <th className="px-4 py-3">Skills proven</th>
              <th className="px-4 py-3">In progress</th>
              <th className="px-4 py-3">Labs completed</th>
              <th className="px-4 py-3">Quizzes passed</th>
              <th className="px-4 py-3">CTF solved</th>
              <th className="px-4 py-3">Investigations passed</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {stats.map((s) => (
              <tr key={s.userId}>
                <td className="px-4 py-3 font-medium text-foreground">{s.name}</td>
                <td className="px-4 py-3 text-foreground-muted">{s.role.replace("_", " ")}</td>
                <td className="px-4 py-3 text-foreground">{s.masteredOrDemonstrated}</td>
                <td className="px-4 py-3 text-foreground-muted">{s.inProgress}</td>
                <td className="px-4 py-3 text-foreground-muted">{s.labsCompleted}</td>
                <td className="px-4 py-3 text-foreground-muted">{s.quizzesPassed}</td>
                <td className="px-4 py-3 text-foreground-muted">{s.ctfSolved}</td>
                <td className="px-4 py-3 text-foreground-muted">{s.investigationsPassed}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function DashboardHeader({ organization }: { organization: { id: string; name: string } }) {
  return (
    <div className="mb-8">
      <Link href={`/orgs/${organization.id}`} className="text-xs text-accent hover:underline">
        &larr; {organization.name}
      </Link>
      <h1 className="mt-1 text-2xl font-semibold text-foreground">Instructor dashboard</h1>
      <p className="mt-1 text-sm text-foreground-muted">
        Real graded results for every member -- skill states, lab completions, quiz/CTF/investigation outcomes.
        Nothing here is self-reported.
      </p>
    </div>
  );
}
