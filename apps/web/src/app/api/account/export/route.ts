import { NextResponse } from "next/server";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

/**
 * Every query below explicitly filters to the caller's own id, even where
 * RLS alone would already restrict most of these tables to "own or staff/
 * instructor." This route's job is "give me MY data," not "give me
 * everything my session happens to be allowed to see" -- an instructor or
 * admin exporting their own data must never see it silently widen to
 * include other users' rows just because their role grants broader read
 * access elsewhere in the app.
 */
export async function GET() {
  const user = await requireUser();
  const supabase = await createClient();

  const [
    profile,
    roles,
    orgMemberships,
    skillEvidence,
    skillStates,
    lessonProgress,
    quizAttempts,
    labInstances,
    labProgress,
    labSubmissions,
    labTerminalCommands,
    ctfSubmissions,
    investigationInstances,
    investigationSubmissions,
    capstoneSubmissions,
    mentorConversations,
    mentorMessages,
    scans,
    subscriptions,
  ] = await Promise.all([
    supabase.from("profiles").select("*").eq("id", user.id).maybeSingle(),
    supabase.from("user_roles").select("role, granted_at").eq("user_id", user.id),
    supabase.from("organization_members").select("organization_id, role, joined_at").eq("user_id", user.id),
    supabase.from("skill_evidence").select("*").eq("user_id", user.id),
    supabase.from("user_skill_states").select("*").eq("user_id", user.id),
    supabase.from("lesson_progress").select("*").eq("user_id", user.id),
    supabase.from("quiz_attempts").select("*").eq("user_id", user.id),
    supabase.from("lab_instances").select("*").eq("user_id", user.id),
    supabase.from("lab_progress").select("*").eq("user_id", user.id),
    supabase.from("lab_submissions").select("*").eq("user_id", user.id),
    supabase.from("lab_terminal_commands").select("*").eq("user_id", user.id),
    supabase.from("ctf_submissions").select("*").eq("user_id", user.id),
    supabase.from("investigation_instances").select("*").eq("user_id", user.id),
    supabase.from("investigation_submissions").select("*").eq("user_id", user.id),
    supabase.from("capstone_submissions").select("*").eq("user_id", user.id),
    supabase.from("mentor_conversations").select("*").eq("user_id", user.id),
    supabase.from("mentor_messages").select("*").eq("user_id", user.id),
    supabase.from("scans").select("*").eq("user_id", user.id),
    supabase.from("subscriptions").select("*").eq("subject_type", "user").eq("subject_id", user.id),
  ]);

  const scanIds = (scans.data ?? []).map((s) => s.id);
  const [scanFiles, scanFindings] = await Promise.all([
    scanIds.length > 0
      ? supabase.from("scan_files").select("*").in("scan_id", scanIds)
      : Promise.resolve({ data: [] }),
    scanIds.length > 0
      ? supabase.from("scan_findings").select("*").in("scan_id", scanIds)
      : Promise.resolve({ data: [] }),
  ]);

  const bundle = {
    exported_at: new Date().toISOString(),
    account: { id: user.id, email: user.email },
    profile: profile.data,
    platform_roles: roles.data ?? [],
    organization_memberships: orgMemberships.data ?? [],
    skill_graph: { evidence: skillEvidence.data ?? [], states: skillStates.data ?? [] },
    lesson_progress: lessonProgress.data ?? [],
    quiz_attempts: quizAttempts.data ?? [],
    labs: {
      instances: labInstances.data ?? [],
      progress: labProgress.data ?? [],
      flag_submissions: labSubmissions.data ?? [],
      terminal_commands: labTerminalCommands.data ?? [],
    },
    ctf_submissions: ctfSubmissions.data ?? [],
    investigations: { instances: investigationInstances.data ?? [], submissions: investigationSubmissions.data ?? [] },
    capstone_submissions: capstoneSubmissions.data ?? [],
    mentor: { conversations: mentorConversations.data ?? [], messages: mentorMessages.data ?? [] },
    scanner: { scans: scans.data ?? [], files: scanFiles.data ?? [], findings: scanFindings.data ?? [] },
    billing: { subscriptions: subscriptions.data ?? [] },
  };

  return new NextResponse(JSON.stringify(bundle, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Content-Disposition": `attachment; filename="icorepen-data-export-${user.id}.json"`,
    },
  });
}
