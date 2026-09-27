// Pure logic for Mentor mode selection -- no I/O, no "server-only" (unlike
// context.ts), because this needs to be importable from the client
// component that renders the mode picker (lib/mentor/context.ts's
// buildMentorContext() is server-only and would break that import).
import type { MentorContextType, MentorMode } from "@/types/database";

/**
 * Single source of truth for every valid MentorMode, mirroring
 * ALL_MENTOR_CONTEXT_TYPES's role for context types (lib/mentor/context.ts)
 * -- previously this list was hand-maintained separately in
 * api/mentor/chat/route.ts, the same drift risk AUDIT-009 found for
 * context types.
 */
export const ALL_MENTOR_MODES: MentorMode[] = [
  "explain",
  "hint",
  "teach",
  "analyze_failure",
  "explain_command",
  "explain_code",
  "explain_finding",
  "guide_investigation",
  "review_report",
  "review_methodology",
  "generate_quiz",
  "prepare_assessment",
  "explain_remediation",
];

/** Always offered, regardless of context -- a user can fall back to a plain explanation from anywhere. */
export const GENERAL_MODES: MentorMode[] = ["explain", "hint", "teach", "analyze_failure"];

export const MODE_LABELS: Record<MentorMode, string> = {
  explain: "Explain",
  hint: "Hint",
  teach: "Teach",
  analyze_failure: "Analyze a failure",
  explain_command: "Explain command",
  explain_code: "Explain code",
  explain_finding: "Explain finding",
  guide_investigation: "Guide investigation",
  review_report: "Review report",
  review_methodology: "Review methodology",
  generate_quiz: "Generate practice quiz",
  prepare_assessment: "Prepare for assessment",
  explain_remediation: "Explain remediation",
};

/**
 * The mode a deep link into /mentor should default to for a given context,
 * mirroring modeInstructions() in prompt.ts -- e.g. opening the Mentor from
 * a scan finding should default to actually discussing that finding
 * (EXPLAIN_FINDING), not the generic EXPLAIN mode. An explicit ?mode= on
 * the URL always overrides this (see /mentor/page.tsx).
 */
export function defaultModeForContext(contextType: MentorContextType): MentorMode {
  switch (contextType) {
    case "lesson":
      return "teach";
    case "lab":
    case "ctf":
      return "hint";
    case "investigation":
      return "guide_investigation";
    case "finding":
      return "explain_finding";
    case "report":
      return "review_report";
    case "skill":
    case "general":
    default:
      return "explain";
  }
}

/**
 * Extra mode pills to offer alongside GENERAL_MODES for a given context --
 * e.g. a finding's chat should let the user switch back to EXPLAIN_FINDING
 * even if they've wandered into HINT, without it ever being hidden.
 * 'report' offers both review modes since either can apply depending on
 * what the user actually wrote (a report page's own deep link picks the
 * right default via ?mode=, but the user may want to try the other lens).
 */
export function extraModesForContext(contextType: MentorContextType): MentorMode[] {
  switch (contextType) {
    case "investigation":
      return ["guide_investigation"];
    case "finding":
      return ["explain_finding"];
    case "report":
      return ["review_report", "review_methodology"];
    default:
      return [];
  }
}
