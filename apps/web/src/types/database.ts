/**
 * Hand-written Supabase database types, matching supabase/migrations/*.sql.
 *
 * These should be regenerated from the live project once one exists:
 *   pnpm dlx supabase gen types typescript --project-id <ref> --schema public > src/types/database.ts
 * (documented in MANUAL_SETUP.md). Hand-written for now because this sandbox
 * has no Docker daemon, which `supabase gen types` requires even against a
 * remote/local --db-url. Only tables the current UI actually queries are
 * covered in full; a few tables further out in the schema (capstones,
 * ctf_events, lab_prerequisites, lab_hint_unlocks) aren't typed here yet --
 * they still exist and work via direct SQL/RPC.
 *
 * Every table/view below declares `Relationships: []` even though real
 * foreign keys exist in SQL -- @supabase/postgrest-js's generic `Database`
 * constraint (GenericTable/GenericView) requires that field to be present at
 * all for its type inference to resolve Row types correctly; omitting it
 * silently collapses every query result to `never` instead of erroring.
 *
 * Row types with more than a couple of fields are declared as standalone
 * `type X = {...}` aliases (never `interface X {...}`) and referenced from
 * `Row:`. This was not a style choice: declaring one as an `interface`
 * silently collapsed EVERY query result across the whole file to `never`
 * (not just that table's), with no diagnostic pointing at the cause.
 * Isolated with a minimal repro (a single `profiles` table, no other
 * tables) -- swapping only `interface ProfileRow {...}` for
 * `type ProfileRow = {...}` was the entire fix. Root cause: postgrest-js's
 * generic Result inference is a deep chain of conditional/mapped types over
 * `Database[Schema]["Tables"][Table]["Row"]`; an `interface` reference
 * apparently doesn't resolve the same way a `type` alias does through that
 * chain in this TypeScript/postgrest-js version combination. If a future
 * table's Row type is added as an `interface` and queries against it start
 * returning `never`, this is almost certainly why -- change it to `type`.
 */

export type SkillState =
  | "NOT_STARTED"
  | "LEARNING"
  | "PRACTICING"
  | "ASSESSED"
  | "DEMONSTRATED"
  | "MASTERED"
  | "NEEDS_REVIEW";

export type PlatformRole = "user" | "instructor" | "moderator" | "admin";

export type UserRoleRow = {
  id: string;
  user_id: string;
  role: PlatformRole;
  granted_by: string | null;
  granted_at: string;
};

export interface AdminUserSearchResult {
  user_id: string;
  email: string | null;
  username: string | null;
  display_name: string | null;
  roles: PlatformRole[];
}

export type OrgRole = "member" | "instructor" | "team_owner" | "org_admin";

export type BillingInterval = "free" | "month" | "year" | "lifetime";
export type SubscriptionStatus = "trialing" | "active" | "past_due" | "canceled" | "expired" | "incomplete";
export type BillingSubjectType = "user" | "organization";
export type WebhookEventStatus = "received" | "processed" | "failed" | "ignored";

export type SubscriptionRow = {
  id: string;
  subject_type: BillingSubjectType;
  subject_id: string;
  plan_id: string;
  status: SubscriptionStatus;
  provider: string | null;
  provider_customer_id: string | null;
  provider_subscription_id: string | null;
  current_period_start: string;
  current_period_end: string | null;
  cancel_at_period_end: boolean;
  trial_end: string | null;
};

export type SkillEvidenceType =
  | "theory"
  | "quiz"
  | "guided_lab"
  | "unguided_lab"
  | "ctf"
  | "assessment"
  | "remediation"
  | "retest"
  | "investigation";

export type SkillEvidenceOutcome = "passed" | "failed" | "partial";

export type QuestionType = "single_choice" | "multi_choice" | "true_false" | "short_answer";
export type HintPolicy = "none" | "limited" | "full";
export type LabCategory =
  | "web"
  | "api"
  | "linux"
  | "windows"
  | "osint"
  | "forensics"
  | "crypto"
  | "reverse_engineering"
  | "cloud"
  | "container"
  | "misc";
export type DifficultyLevel = "beginner" | "easy" | "medium" | "hard" | "insane";
export type LabInstanceStatus = "provisioning" | "running" | "stopped" | "expired" | "destroyed";
export type LabProgressStatus = "not_started" | "in_progress" | "completed" | "failed";

// ---- Row type aliases (see file header for why these aren't looked up via
// Database["public"]["Tables"][...]["Row"] from inside the interface) ----

export type ProfileRow = {
  id: string;
  username: string | null;
  display_name: string | null;
  avatar_url: string | null;
  bio: string | null;
  country: string | null;
  timezone: string;
  locale: string;
  career_goal: string | null;
  onboarding_completed_at: string | null;
  created_at: string;
  updated_at: string;
};

export type OrganizationRow = {
  id: string;
  slug: string;
  name: string;
  created_by: string;
  seat_limit: number | null;
  created_at: string;
  updated_at: string;
};

export type OrganizationMemberRow = {
  id: string;
  organization_id: string;
  user_id: string;
  role: OrgRole;
  invited_by: string | null;
  joined_at: string;
};

export type OrganizationInvitationRow = {
  id: string;
  organization_id: string;
  email: string;
  role: OrgRole;
  invited_by: string;
  token_hash: string;
  expires_at: string;
  accepted_at: string | null;
  revoked_at: string | null;
  created_at: string;
};

export type LearningPathRow = {
  id: string;
  slug: string;
  title: string;
  description: string | null;
  cover_image_url: string | null;
  order_index: number;
  published: boolean;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};

export type ModuleRow = {
  id: string;
  path_id: string;
  slug: string;
  title: string;
  description: string | null;
  order_index: number;
  published: boolean;
  created_at: string;
  updated_at: string;
};

export type LessonRow = {
  id: string;
  module_id: string;
  slug: string;
  title: string;
  summary: string | null;
  content_markdown: string;
  estimated_minutes: number;
  order_index: number;
  published: boolean;
  created_at: string;
  updated_at: string;
};

export type QuizRow = {
  id: string;
  lesson_id: string | null;
  slug: string;
  title: string;
  passing_score: number;
  max_attempts: number | null;
  is_exam: boolean;
  time_limit_minutes: number | null;
  hint_policy: HintPolicy;
  published: boolean;
  created_at: string;
  updated_at: string;
};

export type QuizQuestionRow = {
  id: string;
  quiz_id: string;
  question_text: string;
  question_type: QuestionType;
  order_index: number;
  points: number;
};

export type QuizChoiceRow = {
  id: string;
  question_id: string;
  choice_text: string;
  is_correct: boolean;
  order_index: number;
};

export type QuizAttemptRow = {
  id: string;
  quiz_id: string;
  user_id: string;
  answers: Record<string, unknown>;
  score: number;
  passed: boolean;
  hint_level_used: number;
  submitted_at: string;
};

export type LabRow = {
  id: string;
  slug: string;
  title: string;
  description: string | null;
  category: LabCategory;
  difficulty: DifficultyLevel;
  objectives: unknown;
  has_terminal: boolean;
  estimated_minutes: number;
  points: number;
  supports_guided: boolean;
  supports_unguided: boolean;
  variant_count: number;
  published: boolean;
  created_at: string;
  updated_at: string;
};

export type LabHintRow = {
  id: string;
  lab_id: string;
  level: number;
  content: string;
  point_cost: number;
};

export type LabFlagRow = {
  id: string;
  lab_id: string;
  label: string;
  flag_hash: string;
  variant_seed: number;
};

export type LabEnvironmentRow = {
  id: string;
  lab_id: string;
  variant_seed: number;
  spec: unknown;
  created_at: string;
  updated_at: string;
};

export type LabTerminalCommandRow = {
  id: number;
  lab_instance_id: string;
  user_id: string;
  command: string;
  output: string;
  cwd_before: string;
  cwd_after: string;
  created_at: string;
};

export type LabInstanceRow = {
  id: string;
  lab_id: string;
  user_id: string;
  guided: boolean;
  status: LabInstanceStatus;
  variant_seed: number;
  environment_state: Record<string, unknown>;
  started_at: string;
  expires_at: string | null;
  destroyed_at: string | null;
};

export type LabSubmissionRow = {
  id: string;
  lab_instance_id: string;
  user_id: string;
  flag_id: string | null;
  correct: boolean;
  submitted_at: string;
};

export type LabProgressRow = {
  id: string;
  user_id: string;
  lab_id: string;
  status: LabProgressStatus;
  attempts: number;
  first_completed_at: string | null;
  last_attempt_at: string | null;
};

export type CtfChallengeRow = {
  id: string;
  event_id: string | null;
  lab_id: string | null;
  slug: string;
  title: string;
  description: string | null;
  category: LabCategory;
  difficulty: DifficultyLevel;
  points: number;
  flag_hash: string;
  published: boolean;
};

export type CtfSubmissionRow = {
  id: string;
  challenge_id: string;
  user_id: string;
  correct: boolean;
  points_awarded: number;
  submitted_at: string;
};

export type CapstoneStatus = "submitted" | "under_review" | "passed" | "needs_revision";

export type CapstoneRow = {
  id: string;
  slug: string;
  title: string;
  description: string | null;
  report_required: boolean;
  published: boolean;
  created_at: string;
};

export type CapstoneSubmissionRow = {
  id: string;
  capstone_id: string;
  user_id: string;
  report_content: string | null;
  status: CapstoneStatus;
  reviewer_id: string | null;
  reviewer_notes: string | null;
  submitted_at: string;
  reviewed_at: string | null;
};

export type InvestigationArtifactType =
  | "whois_record"
  | "email_headers"
  | "social_media_profile"
  | "file_metadata"
  | "log_excerpt"
  | "network_capture_summary"
  | "document_excerpt"
  | "chat_transcript";
export type InvestigationQuestionType = "exact_text" | "multiple_choice";

export type InvestigationRow = {
  id: string;
  slug: string;
  title: string;
  briefing: string | null;
  category: LabCategory;
  difficulty: DifficultyLevel;
  objectives: unknown;
  estimated_minutes: number;
  points: number;
  passing_score: number;
  published: boolean;
  created_at: string;
  updated_at: string;
};

export type InvestigationArtifactRow = {
  id: string;
  investigation_id: string;
  artifact_type: InvestigationArtifactType;
  title: string;
  content: string;
  order_index: number;
};

export type InvestigationQuestionRow = {
  id: string;
  investigation_id: string;
  question_text: string;
  question_type: InvestigationQuestionType;
  order_index: number;
  points: number;
  answer_hash: string | null;
};

export type InvestigationChoiceRow = {
  id: string;
  question_id: string;
  choice_text: string;
  is_correct: boolean;
  order_index: number;
};

export type InvestigationInstanceRow = {
  id: string;
  investigation_id: string;
  user_id: string;
  notes: string;
  started_at: string;
  updated_at: string;
};

export type InvestigationSubmissionRow = {
  id: string;
  investigation_id: string;
  user_id: string;
  answers: Record<string, unknown>;
  score: number;
  passed: boolean;
  submitted_at: string;
};

export type MentorContextType = "skill" | "lesson" | "lab" | "ctf" | "general";
export type MentorMode =
  | "explain"
  | "hint"
  | "teach"
  | "analyze_failure"
  | "explain_command"
  | "explain_finding"
  | "explain_code"
  | "guide_investigation"
  | "review_methodology"
  | "generate_quiz"
  | "prepare_assessment"
  | "explain_remediation"
  | "review_report";
export type MentorMessageRole = "user" | "assistant";

export type MentorConversationRow = {
  id: string;
  user_id: string;
  context_type: MentorContextType;
  context_id: string | null;
  title: string | null;
  created_at: string;
  updated_at: string;
};

export type MentorMessageRow = {
  id: string;
  conversation_id: string;
  user_id: string;
  role: MentorMessageRole;
  mode: MentorMode | null;
  content: string;
  created_at: string;
};

export type ScanStatus = "queued" | "running" | "completed" | "failed";
export type ScanTargetType = "pasted_snippet" | "uploaded_files";
export type ScanFindingSeverity = "critical" | "high" | "medium" | "low" | "info";
export type ScanFindingConfidence = "high" | "medium" | "low";
export type ScanFindingCategory =
  | "secrets"
  | "sql_injection"
  | "xss"
  | "command_injection"
  | "path_traversal"
  | "insecure_eval"
  | "weak_cryptography"
  | "insecure_cors"
  | "insecure_cookies"
  | "cleartext_http"
  | "prototype_pollution"
  | "unsafe_deserialization"
  | "other";
export type ScanFindingVerificationStatus = "true_positive" | "false_positive" | "needs_review" | "informational";
export type ScanFindingStatus =
  | "discovered"
  | "remediation_required"
  | "fix_applied"
  | "retested"
  | "verified_fixed"
  | "false_positive"
  | "wont_fix";

export type ScanRow = {
  id: string;
  user_id: string;
  title: string;
  target_type: ScanTargetType;
  status: ScanStatus;
  total_files: number;
  total_findings: number;
  findings_by_severity: Record<string, number>;
  error_message: string | null;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
};

export type ScanFileRow = {
  id: string;
  scan_id: string;
  filename: string;
  language: string | null;
  content: string;
  size_bytes: number;
  content_sha256: string;
  created_at: string;
};

export type ReferenceLink = { title: string; url: string };

export type ScanFindingRow = {
  id: string;
  scan_id: string;
  file_id: string;
  rule_id: string;
  category: ScanFindingCategory;
  title: string;
  severity: ScanFindingSeverity;
  confidence: ScanFindingConfidence;
  line_start: number;
  line_end: number;
  evidence: string;
  explanation: string;
  impact: string;
  remediation: string;
  secure_example: string | null;
  reference_links: ReferenceLink[];
  verification_status: ScanFindingVerificationStatus;
  ai_enriched: boolean;
  status: ScanFindingStatus;
  created_at: string;
  updated_at: string;
};

export type ScanFindingStatusEventRow = {
  id: number;
  finding_id: string;
  actor_id: string;
  from_status: ScanFindingStatus;
  to_status: ScanFindingStatus;
  note: string | null;
  created_at: string;
};

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: ProfileRow;
        Insert: Partial<ProfileRow> & { id: string };
        Update: Partial<ProfileRow>;
        Relationships: [];
      };
      user_roles: {
        Row: UserRoleRow;
        // App code never inserts here directly -- see the
        // grant_platform_role()/revoke_platform_role() RPCs below, called
        // from app/(app)/admin/users/actions.ts.
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      skill_categories: {
        Row: { id: string; slug: string; name: string; sort_order: number };
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      skills: {
        Row: {
          id: string;
          slug: string;
          name: string;
          category_id: string;
          description: string | null;
          created_at: string;
          updated_at: string;
        };
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      skill_prerequisites: {
        Row: { skill_id: string; prerequisite_skill_id: string };
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      user_skill_states: {
        Row: {
          user_id: string;
          skill_id: string;
          state: SkillState;
          updated_at: string;
        };
        Insert: Record<string, never>; // written only by recompute_skill_state()
        Update: Record<string, never>;
        Relationships: [];
      };
      skill_evidence: {
        Row: {
          id: string;
          seq: number;
          user_id: string;
          skill_id: string;
          evidence_type: SkillEvidenceType;
          outcome: SkillEvidenceOutcome;
          source_type: string;
          source_id: string | null;
          score: number | null;
          hint_level_used: number | null;
          metadata: Record<string, unknown>;
          occurred_at: string;
        };
        Insert: Record<string, never>; // written only by record_skill_evidence()
        Update: Record<string, never>;
        Relationships: [];
      };
      plans: {
        Row: {
          id: string;
          slug: string;
          name: string;
          description: string | null;
          price_cents: number;
          currency: string;
          interval: BillingInterval;
          is_active: boolean;
          sort_order: number;
        };
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      plan_entitlements: {
        Row: { plan_id: string; key: string; value: unknown };
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      subscriptions: {
        Row: SubscriptionRow;
        Insert: Record<string, never>; // written only by set_active_subscription()
        Update: Record<string, never>;
        Relationships: [
          {
            foreignKeyName: "subscriptions_plan_id_fkey";
            columns: ["plan_id"];
            isOneToOne: false;
            referencedRelation: "plans";
            referencedColumns: ["id"];
          },
        ];
      };
      billing_webhook_events: {
        Row: {
          id: string;
          provider: string;
          provider_event_id: string;
          event_type: string;
          payload: Record<string, unknown>;
          status: WebhookEventStatus;
          error: string | null;
          received_at: string;
          processed_at: string | null;
        };
        // Only service_role writes here (the webhook handlers) -- no RLS
        // INSERT/UPDATE policy exists for authenticated/anon at all.
        Insert: {
          provider: string;
          provider_event_id: string;
          event_type: string;
          payload: Record<string, unknown>;
          status?: WebhookEventStatus;
        };
        Update: Partial<{ status: WebhookEventStatus; error: string | null; processed_at: string | null }>;
        Relationships: [];
      };
      organizations: {
        Row: OrganizationRow;
        Insert: { slug: string; name: string; created_by: string };
        Update: Partial<{ name: string; seat_limit: number | null }>;
        Relationships: [];
      };
      organization_members: {
        Row: OrganizationMemberRow;
        // A member's own row is inserted only by the handle_new_organization()
        // trigger or accept_organization_invitation(); an org admin adding
        // someone directly still goes through this table's real INSERT RLS
        // policy (org_members_write_org_admin), not a client-trusted role.
        Insert: { organization_id: string; user_id: string; role?: OrgRole; invited_by?: string | null };
        Update: Partial<{ role: OrgRole }>;
        Relationships: [];
      };
      organization_invitations: {
        Row: OrganizationInvitationRow;
        // Never inserted directly from the client -- the raw token must be
        // generated and hashed server-side. See create_organization_invitation().
        Insert: Record<string, never>;
        Update: Partial<{ revoked_at: string }>;
        Relationships: [];
      };

      // ---- Content model: authoring tables (staff read/write via RLS) ----

      learning_paths: {
        Row: LearningPathRow;
        Insert: Partial<LearningPathRow> & { slug: string; title: string };
        Update: Partial<LearningPathRow>;
        Relationships: [];
      };
      modules: {
        Row: ModuleRow;
        Insert: Partial<ModuleRow> & { path_id: string; slug: string; title: string };
        Update: Partial<ModuleRow>;
        Relationships: [];
      };
      lessons: {
        Row: LessonRow;
        Insert: Partial<LessonRow> & { module_id: string; slug: string; title: string };
        Update: Partial<LessonRow>;
        Relationships: [];
      };
      lesson_skills: {
        Row: { lesson_id: string; skill_id: string };
        Insert: { lesson_id: string; skill_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      lesson_progress: {
        Row: {
          id: string;
          user_id: string;
          lesson_id: string;
          completed_at: string | null;
          time_spent_seconds: number;
        };
        Insert: { user_id: string; lesson_id: string; completed_at?: string | null; time_spent_seconds?: number };
        Update: Partial<{ completed_at: string | null; time_spent_seconds: number }>;
        Relationships: [];
      };

      quizzes: {
        Row: QuizRow;
        Insert: Partial<QuizRow> & { slug: string; title: string };
        Update: Partial<QuizRow>;
        Relationships: [];
      };
      quiz_skills: {
        Row: { quiz_id: string; skill_id: string };
        Insert: { quiz_id: string; skill_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      quiz_questions: {
        Row: QuizQuestionRow;
        Insert: Partial<QuizQuestionRow> & { quiz_id: string; question_text: string };
        Update: Partial<QuizQuestionRow>;
        Relationships: [];
      };
      quiz_choices: {
        Row: QuizChoiceRow;
        Insert: Partial<QuizChoiceRow> & { question_id: string; choice_text: string };
        Update: Partial<QuizChoiceRow>;
        Relationships: [];
      };
      quiz_attempts: {
        Row: QuizAttemptRow;
        Insert: Record<string, never>; // written only by submit_quiz_attempt()
        Update: Record<string, never>;
        Relationships: [];
      };

      labs: {
        Row: LabRow;
        Insert: Partial<LabRow> & {
          slug: string;
          title: string;
          category: LabCategory;
          difficulty: DifficultyLevel;
        };
        Update: Partial<LabRow>;
        Relationships: [];
      };
      lab_skills: {
        Row: { lab_id: string; skill_id: string };
        Insert: { lab_id: string; skill_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      lab_hints: {
        Row: LabHintRow;
        Insert: Partial<LabHintRow> & { lab_id: string; level: number; content: string };
        Update: Partial<LabHintRow>;
        Relationships: [];
      };
      lab_flags: {
        Row: LabFlagRow;
        // flag_hash must only ever be written by a server action that hashes
        // the plaintext server-side (see apps/web/src/lib/security/flag-hash.ts)
        Insert: { lab_id: string; label: string; flag_hash: string; variant_seed?: number };
        Update: Record<string, never>;
        Relationships: [];
      };
      lab_instances: {
        Row: LabInstanceRow;
        Insert: { lab_id: string; user_id: string; guided: boolean; status?: LabInstanceStatus };
        Update: Partial<{ status: LabInstanceStatus; environment_state: Record<string, unknown> }>;
        Relationships: [];
      };
      lab_environments: {
        Row: LabEnvironmentRow;
        // Never inserted/updated from a user-session client -- staff-only by
        // RLS; authoring goes through the admin UI, which uses this same
        // owner-authenticated-as-staff session (no service-role bypass
        // needed there, unlike the terminal's own read path -- see ADR 0009).
        Insert: { lab_id: string; variant_seed?: number; spec: Record<string, unknown> };
        Update: Partial<{ spec: Record<string, unknown> }>;
        Relationships: [];
      };
      lab_terminal_commands: {
        Row: LabTerminalCommandRow;
        Insert: {
          lab_instance_id: string;
          user_id: string;
          command: string;
          output: string;
          cwd_before: string;
          cwd_after: string;
        };
        Update: Record<string, never>;
        Relationships: [];
      };
      lab_hint_unlocks: {
        Row: { id: string; lab_instance_id: string; hint_id: string; unlocked_at: string };
        Insert: Record<string, never>; // written only by unlock_lab_hint()
        Update: Record<string, never>;
        Relationships: [];
      };
      lab_submissions: {
        Row: LabSubmissionRow;
        Insert: Record<string, never>; // written only by submit_lab_flag()
        Update: Record<string, never>;
        Relationships: [];
      };
      lab_progress: {
        Row: LabProgressRow;
        Insert: Record<string, never>; // written only by submit_lab_flag()
        Update: Record<string, never>;
        Relationships: [];
      };

      ctf_challenges: {
        Row: CtfChallengeRow;
        // flag_hash must only ever be written by a server action that hashes
        // the plaintext server-side (see apps/web/src/lib/security/flag-hash.ts)
        Insert: Partial<CtfChallengeRow> & {
          slug: string;
          title: string;
          category: LabCategory;
          difficulty: DifficultyLevel;
          flag_hash: string;
        };
        Update: Partial<CtfChallengeRow>;
        Relationships: [];
      };
      ctf_challenge_skills: {
        Row: { challenge_id: string; skill_id: string };
        Insert: { challenge_id: string; skill_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      ctf_submissions: {
        Row: CtfSubmissionRow;
        Insert: Record<string, never>; // written only by submit_ctf_flag()
        Update: Record<string, never>;
        Relationships: [];
      };

      capstones: {
        Row: CapstoneRow;
        Insert: Partial<CapstoneRow> & { slug: string; title: string };
        Update: Partial<CapstoneRow>;
        Relationships: [];
      };
      capstone_skills: {
        Row: { capstone_id: string; skill_id: string };
        Insert: { capstone_id: string; skill_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      capstone_labs: {
        Row: { capstone_id: string; lab_id: string };
        Insert: { capstone_id: string; lab_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      capstone_submissions: {
        Row: CapstoneSubmissionRow;
        // Status/reviewer fields only ever change via review_capstone_submission().
        Insert: { capstone_id: string; user_id: string; report_content?: string | null };
        Update: Record<string, never>;
        Relationships: [];
      };

      investigations: {
        Row: InvestigationRow;
        Insert: Partial<InvestigationRow> & { slug: string; title: string; category: LabCategory; difficulty: DifficultyLevel };
        Update: Partial<InvestigationRow>;
        Relationships: [];
      };
      investigation_skills: {
        Row: { investigation_id: string; skill_id: string };
        Insert: { investigation_id: string; skill_id: string };
        Update: Record<string, never>;
        Relationships: [];
      };
      investigation_artifacts: {
        Row: InvestigationArtifactRow;
        Insert: Partial<InvestigationArtifactRow> & {
          investigation_id: string;
          artifact_type: InvestigationArtifactType;
          title: string;
          content: string;
        };
        Update: Partial<InvestigationArtifactRow>;
        Relationships: [];
      };
      investigation_questions: {
        Row: InvestigationQuestionRow;
        Insert: Partial<InvestigationQuestionRow> & {
          investigation_id: string;
          question_text: string;
          question_type: InvestigationQuestionType;
        };
        Update: Partial<InvestigationQuestionRow>;
        Relationships: [];
      };
      investigation_choices: {
        Row: InvestigationChoiceRow;
        Insert: Partial<InvestigationChoiceRow> & { question_id: string; choice_text: string };
        Update: Partial<InvestigationChoiceRow>;
        Relationships: [];
      };
      investigation_instances: {
        Row: InvestigationInstanceRow;
        Insert: { investigation_id: string; user_id: string; notes?: string };
        Update: Partial<{ notes: string }>;
        Relationships: [];
      };
      investigation_submissions: {
        Row: InvestigationSubmissionRow;
        Insert: Record<string, never>; // written only by submit_investigation_answers()
        Update: Record<string, never>;
        Relationships: [];
      };

      mentor_conversations: {
        Row: MentorConversationRow;
        Insert: { user_id: string; context_type?: MentorContextType; context_id?: string | null; title?: string | null };
        Update: Partial<{ title: string | null }>;
        Relationships: [];
      };
      mentor_messages: {
        Row: MentorMessageRow;
        Insert: {
          conversation_id: string;
          user_id: string;
          role: MentorMessageRole;
          mode?: MentorMode | null;
          content: string;
        };
        Update: Record<string, never>;
        Relationships: [];
      };

      scans: {
        Row: ScanRow;
        Insert: {
          user_id: string;
          title: string;
          target_type: ScanTargetType;
          status?: ScanStatus;
          error_message?: string | null;
          started_at?: string | null;
          completed_at?: string | null;
        };
        Update: Partial<{
          status: ScanStatus;
          error_message: string | null;
          started_at: string | null;
          completed_at: string | null;
        }>;
        Relationships: [];
      };
      scan_files: {
        Row: ScanFileRow;
        Insert: {
          scan_id: string;
          filename: string;
          language?: string | null;
          content: string;
          size_bytes: number;
          content_sha256: string;
        };
        Update: Record<string, never>;
        Relationships: [];
      };
      scan_findings: {
        Row: ScanFindingRow;
        Insert: {
          scan_id: string;
          file_id: string;
          rule_id: string;
          category: ScanFindingCategory;
          title: string;
          severity: ScanFindingSeverity;
          confidence: ScanFindingConfidence;
          line_start: number;
          line_end: number;
          evidence: string;
          explanation: string;
          impact: string;
          remediation: string;
          secure_example?: string | null;
          reference_links?: ReferenceLink[];
          verification_status?: ScanFindingVerificationStatus;
        };
        Update: Record<string, never>; // status changes only via transition_scan_finding_status()
        Relationships: [];
      };
      scan_finding_status_events: {
        Row: ScanFindingStatusEventRow;
        Insert: Record<string, never>; // written only by transition_scan_finding_status()
        Update: Record<string, never>;
        Relationships: [];
      };
    };
    Views: {
      quiz_questions_for_attempt: {
        Row: {
          quiz_id: string;
          slug: string;
          title: string;
          passing_score: number;
          max_attempts: number | null;
          is_exam: boolean;
          time_limit_minutes: number | null;
          hint_policy: HintPolicy;
          question_id: string;
          question_text: string;
          question_type: QuestionType;
          order_index: number;
          points: number;
          choice_id: string | null;
          choice_text: string | null;
          choice_order_index: number | null;
        };
        Relationships: [];
      };
      ctf_challenges_public: {
        Row: {
          id: string;
          event_id: string | null;
          lab_id: string | null;
          slug: string;
          title: string;
          description: string | null;
          category: LabCategory;
          difficulty: DifficultyLevel;
          points: number;
          published: boolean;
        };
        Relationships: [];
      };
      investigation_questions_for_attempt: {
        Row: {
          investigation_id: string;
          slug: string;
          title: string;
          passing_score: number;
          question_id: string;
          question_text: string;
          question_type: InvestigationQuestionType;
          order_index: number;
          points: number;
          choice_id: string | null;
          choice_text: string | null;
          choice_order_index: number | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      get_entitlement: {
        Args: { p_subject_type: "user" | "organization"; p_subject_id: string; p_key: string };
        Returns: unknown;
      };
      submit_quiz_attempt: {
        Args: { p_quiz_id: string; p_answers: Record<string, string[]> };
        Returns: QuizAttemptRow;
      };
      submit_lab_flag: {
        Args: { p_lab_instance_id: string; p_flag: string };
        Returns: LabSubmissionRow;
      };
      submit_ctf_flag: {
        Args: { p_challenge_id: string; p_flag: string };
        Returns: CtfSubmissionRow;
      };
      submit_investigation_answers: {
        Args: { p_investigation_id: string; p_answers: Record<string, string[] | string> };
        Returns: InvestigationSubmissionRow;
      };
      unlock_lab_hint: {
        Args: { p_lab_instance_id: string; p_hint_id: string };
        Returns: { lab_instance_id: string; hint_id: string; unlocked_at: string };
      };
      log_audit_event: {
        Args: {
          p_action: string;
          p_target_type?: string | null;
          p_target_id?: string | null;
          p_organization_id?: string | null;
          p_metadata?: Record<string, unknown>;
        };
        Returns: number;
      };
      transition_scan_finding_status: {
        Args: { p_finding_id: string; p_new_status: ScanFindingStatus; p_note?: string | null };
        Returns: ScanFindingRow;
      };
      enrich_scan_finding: {
        Args: {
          p_finding_id: string;
          p_explanation: string;
          p_impact: string;
          p_remediation: string;
          p_secure_example?: string | null;
        };
        Returns: ScanFindingRow;
      };
      count_my_scan_enrichments_today: {
        Args: Record<string, never>;
        Returns: number;
      };
      grant_platform_role: {
        Args: { p_user_id: string; p_role: PlatformRole };
        Returns: UserRoleRow;
      };
      revoke_platform_role: {
        Args: { p_user_id: string; p_role: PlatformRole };
        Returns: void;
      };
      admin_search_users: {
        Args: { p_query?: string };
        Returns: AdminUserSearchResult[];
      };
      set_active_subscription: {
        Args: {
          p_subject_type: BillingSubjectType;
          p_subject_id: string;
          p_plan_id: string;
          p_status: SubscriptionStatus;
          p_provider: string | null;
          p_provider_customer_id?: string | null;
          p_provider_subscription_id?: string | null;
          p_current_period_end?: string | null;
          p_trial_end?: string | null;
        };
        Returns: SubscriptionRow;
      };
      review_capstone_submission: {
        Args: { p_submission_id: string; p_status: CapstoneStatus; p_notes?: string | null };
        Returns: CapstoneSubmissionRow;
      };
      create_organization_invitation: {
        Args: { p_organization_id: string; p_email: string; p_role?: OrgRole };
        Returns: string;
      };
      accept_organization_invitation: {
        Args: { p_token: string };
        Returns: OrganizationMemberRow;
      };
      update_organization_member_role: {
        Args: { p_organization_id: string; p_organization_member_id: string; p_new_role: OrgRole };
        Returns: OrganizationMemberRow;
      };
      remove_organization_member: {
        Args: { p_organization_id: string; p_organization_member_id: string };
        Returns: void;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
}
