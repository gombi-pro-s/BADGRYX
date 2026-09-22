import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database, MentorContextType } from "@/types/database";

export interface SkillStateSummary {
  name: string;
  category: string;
  state: string;
}

export interface EvidenceSummary {
  skillName: string;
  evidenceType: string;
  outcome: string;
  occurredAt: string;
}

export interface FocusDetail {
  type: MentorContextType;
  title: string;
  description: string | null;
  /** Only hints the user has actually unlocked for this lab -- never the flag, never locked hint content. */
  unlockedHints?: string[];
}

export interface MentorContext {
  displayName: string;
  skillStates: SkillStateSummary[];
  recentEvidence: EvidenceSummary[];
  focus: FocusDetail | null;
}

const MAX_SKILL_STATES = 25;
const MAX_RECENT_EVIDENCE = 15;

/**
 * Pulls everything the Mentor is allowed to reason about, straight from the
 * database, for the CURRENT authenticated user only (the caller's own
 * Supabase client, subject to RLS -- this function cannot be used to build
 * another user's context because the underlying queries simply wouldn't
 * return another user's rows). Nothing here is invented; every field traces
 * to a real row. See lib/mentor/prompt.ts for how this becomes "TRUSTED
 * APPLICATION DATA" in the system prompt, kept separate from untrusted user
 * input.
 */
export async function buildMentorContext(
  supabase: SupabaseClient<Database>,
  userId: string,
  focusType: MentorContextType,
  focusId: string | null,
): Promise<MentorContext> {
  const [{ data: profile }, { data: states }, { data: evidence }] = await Promise.all([
    supabase.from("profiles").select("display_name").eq("id", userId).single(),
    supabase
      .from("user_skill_states")
      .select("state, skills(name, skill_categories(name))")
      .eq("user_id", userId)
      .neq("state", "NOT_STARTED")
      .limit(MAX_SKILL_STATES),
    supabase
      .from("skill_evidence")
      .select("evidence_type, outcome, occurred_at, skills(name)")
      .eq("user_id", userId)
      .order("occurred_at", { ascending: false })
      .limit(MAX_RECENT_EVIDENCE),
  ]);

  const skillStates: SkillStateSummary[] = (states ?? []).map((row) => {
    const skill = row.skills as unknown as { name: string; skill_categories: { name: string } | null } | null;
    return {
      name: skill?.name ?? "unknown skill",
      category: skill?.skill_categories?.name ?? "unknown",
      state: row.state,
    };
  });

  const recentEvidence: EvidenceSummary[] = (evidence ?? []).map((row) => {
    const skill = row.skills as unknown as { name: string } | null;
    return {
      skillName: skill?.name ?? "unknown skill",
      evidenceType: row.evidence_type,
      outcome: row.outcome,
      occurredAt: row.occurred_at,
    };
  });

  const focus = await buildFocusDetail(supabase, userId, focusType, focusId);

  return {
    displayName: profile?.display_name ?? "there",
    skillStates,
    recentEvidence,
    focus,
  };
}

async function buildFocusDetail(
  supabase: SupabaseClient<Database>,
  userId: string,
  focusType: MentorContextType,
  focusId: string | null,
): Promise<FocusDetail | null> {
  if (!focusId || focusType === "general") return null;

  if (focusType === "skill") {
    const { data } = await supabase.from("skills").select("name, description").eq("id", focusId).maybeSingle();
    if (!data) return null;
    return { type: "skill", title: data.name, description: data.description };
  }

  if (focusType === "lesson") {
    const { data } = await supabase.from("lessons").select("title, summary").eq("id", focusId).maybeSingle();
    if (!data) return null;
    return { type: "lesson", title: data.title, description: data.summary };
  }

  if (focusType === "lab") {
    const { data: lab } = await supabase.from("labs").select("title, description").eq("id", focusId).maybeSingle();
    if (!lab) return null;

    // Only hints this specific user has actually unlocked, for their most
    // recent instance of this lab -- never the full hint list, never a
    // locked hint's content, and never the flag (lab_flags isn't queried
    // here at all).
    const { data: instance } = await supabase
      .from("lab_instances")
      .select("id")
      .eq("lab_id", focusId)
      .eq("user_id", userId)
      .order("started_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    let unlockedHints: string[] = [];
    if (instance) {
      const { data: unlocks } = await supabase
        .from("lab_hint_unlocks")
        .select("lab_hints(content)")
        .eq("lab_instance_id", instance.id);
      unlockedHints = (unlocks ?? [])
        .map((row) => (row.lab_hints as unknown as { content: string } | null)?.content)
        .filter((c): c is string => !!c);
    }

    return { type: "lab", title: lab.title, description: lab.description, unlockedHints };
  }

  if (focusType === "ctf") {
    const { data } = await supabase
      .from("ctf_challenges_public")
      .select("title, description")
      .eq("id", focusId)
      .maybeSingle();
    if (!data) return null;
    return { type: "ctf", title: data.title, description: data.description };
  }

  if (focusType === "investigation") {
    const { data } = await supabase
      .from("investigations")
      .select("title, briefing")
      .eq("id", focusId)
      .maybeSingle();
    if (!data) return null;
    return { type: "investigation", title: data.title, description: data.briefing };
  }

  if (focusType === "finding") {
    // RLS on scan_findings is owner-scoped (via its scan) + staff-readable,
    // exactly like every other table queried here -- this can never return
    // another user's finding through the caller's own client.
    const { data } = await supabase
      .from("scan_findings")
      .select("title, category, severity, evidence, explanation, impact, remediation")
      .eq("id", focusId)
      .maybeSingle();
    if (!data) return null;
    const description = [
      `Category: ${data.category} | Severity: ${data.severity}`,
      `Evidence (the actual flagged code):\n${data.evidence}`,
      `Explanation: ${data.explanation}`,
      `Impact: ${data.impact}`,
      `Remediation: ${data.remediation}`,
    ].join("\n\n");
    return { type: "finding", title: data.title, description };
  }

  return null;
}
