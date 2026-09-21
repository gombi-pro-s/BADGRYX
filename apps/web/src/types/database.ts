/**
 * Hand-written Supabase database types, matching supabase/migrations/*.sql.
 *
 * These should be regenerated from the live project once one exists:
 *   pnpm dlx supabase gen types typescript --project-id <ref> --schema public > src/types/database.ts
 * (documented in MANUAL_SETUP.md). Hand-written for now because this sandbox
 * has no Docker daemon, which `supabase gen types` requires even against a
 * remote/local --db-url. Only tables the current UI actually queries are
 * covered in full; everything else in the schema still exists and works via
 * direct SQL/RPC, it just isn't typed here yet.
 *
 * Every table/view below declares `Relationships: []` even though real
 * foreign keys exist in SQL -- @supabase/postgrest-js's generic `Database`
 * constraint (GenericTable/GenericView) requires that field to be present at
 * all for its type inference to resolve Row types correctly; omitting it
 * silently collapses every query result to `never` instead of erroring.
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

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
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
        Insert: Partial<Database["public"]["Tables"]["profiles"]["Row"]> & {
          id: string;
        };
        Update: Partial<Database["public"]["Tables"]["profiles"]["Row"]>;
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
          status:
            | "trialing"
            | "active"
            | "past_due"
            | "canceled"
            | "expired"
            | "incomplete";
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
    };
    Views: {
      quiz_questions_for_attempt: {
        Row: {
          quiz_id: string;
          slug: string;
          title: string;
          passing_score: number;
          question_id: string;
          question_text: string;
          question_type: string;
          choice_id: string | null;
          choice_text: string | null;
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
          category: string;
          difficulty: string;
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
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
}
