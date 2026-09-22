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

export type SkillEvidenceType =
  | "theory"
  | "quiz"
  | "guided_lab"
  | "unguided_lab"
  | "ctf"
  | "assessment"
  | "remediation"
  | "retest";

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
  environment_spec: unknown;
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
        Row: {
          id: string;
          user_id: string;
          role: PlatformRole;
          granted_by: string | null;
          granted_at: string;
        };
        Insert: Record<string, never>; // writes only via admin RLS path, never raw client insert in app code
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
          interval: "free" | "month" | "year" | "lifetime";
          is_active: boolean;
          sort_order: number;
        };
        Insert: Record<string, never>;
        Update: Record<string, never>;
        Relationships: [];
      };
      subscriptions: {
        Row: {
          id: string;
          subject_type: "user" | "organization";
          subject_id: string;
          plan_id: string;
          status: "trialing" | "active" | "past_due" | "canceled" | "expired" | "incomplete";
          provider: string | null;
          current_period_end: string | null;
        };
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
      organizations: {
        Row: {
          id: string;
          slug: string;
          name: string;
          created_by: string;
          seat_limit: number | null;
          created_at: string;
          updated_at: string;
        };
        Insert: { slug: string; name: string; created_by: string };
        Update: Partial<{ name: string; seat_limit: number | null }>;
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
        Update: Partial<{ status: LabInstanceStatus }>;
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
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
}
