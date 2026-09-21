-- ============================================================================
-- Content model: learning paths -> modules -> lessons/quizzes, labs, CTF,
-- capstones. Structured so an admin CMS can author content as data, never
-- as hardcoded frontend components (section 29/59).
--
-- Grading logic (quiz scoring, lab flag verification, CTF scoring) lives in
-- 20260921000010_grading_and_evidence.sql alongside skill_evidence writes,
-- once every content table it touches exists.
-- ============================================================================

CREATE TYPE public.difficulty_level AS ENUM ('beginner', 'easy', 'medium', 'hard', 'insane');

-- ----------------------------------------------------------------------------
-- Learning paths / modules / lessons
-- ----------------------------------------------------------------------------

CREATE TABLE public.learning_paths (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  cover_image_url text,
  order_index integer NOT NULL DEFAULT 0,
  published boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES auth.users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path_id uuid NOT NULL REFERENCES public.learning_paths (id) ON DELETE CASCADE,
  slug text NOT NULL,
  title text NOT NULL,
  description text,
  order_index integer NOT NULL DEFAULT 0,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (path_id, slug)
);

CREATE INDEX modules_path_id_idx ON public.modules (path_id);

CREATE TABLE public.lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_id uuid NOT NULL REFERENCES public.modules (id) ON DELETE CASCADE,
  slug text NOT NULL,
  title text NOT NULL,
  summary text,
  content_markdown text NOT NULL DEFAULT '',
  estimated_minutes integer NOT NULL DEFAULT 10,
  order_index integer NOT NULL DEFAULT 0,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (module_id, slug)
);

CREATE INDEX lessons_module_id_idx ON public.lessons (module_id);

CREATE TABLE public.lesson_skills (
  lesson_id uuid NOT NULL REFERENCES public.lessons (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (lesson_id, skill_id)
);

CREATE TABLE public.lesson_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL REFERENCES public.lessons (id) ON DELETE CASCADE,
  completed_at timestamptz,
  time_spent_seconds integer NOT NULL DEFAULT 0,
  UNIQUE (user_id, lesson_id)
);

CREATE INDEX lesson_progress_user_id_idx ON public.lesson_progress (user_id);

-- ----------------------------------------------------------------------------
-- Quizzes (also used for exams -- see is_exam/time_limit_minutes/hint_policy;
-- see docs/adr/0004-content-model.md for why exams reuse this table instead
-- of a parallel schema).
-- ----------------------------------------------------------------------------

CREATE TYPE public.question_type AS ENUM ('single_choice', 'multi_choice', 'true_false', 'short_answer');
CREATE TYPE public.hint_policy AS ENUM ('none', 'limited', 'full');

CREATE TABLE public.quizzes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid REFERENCES public.lessons (id) ON DELETE CASCADE,
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  passing_score numeric NOT NULL DEFAULT 70 CHECK (passing_score BETWEEN 0 AND 100),
  max_attempts integer,
  is_exam boolean NOT NULL DEFAULT false,
  time_limit_minutes integer,
  hint_policy public.hint_policy NOT NULL DEFAULT 'full',
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.quiz_skills (
  quiz_id uuid NOT NULL REFERENCES public.quizzes (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (quiz_id, skill_id)
);

CREATE TABLE public.quiz_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quiz_id uuid NOT NULL REFERENCES public.quizzes (id) ON DELETE CASCADE,
  question_text text NOT NULL,
  question_type public.question_type NOT NULL DEFAULT 'single_choice',
  order_index integer NOT NULL DEFAULT 0,
  points numeric NOT NULL DEFAULT 1
);

CREATE INDEX quiz_questions_quiz_id_idx ON public.quiz_questions (quiz_id);

-- Correctness lives only here. This table is never directly selectable by
-- authenticated/anon (see RLS migration) -- clients read questions/choices
-- through the public.quiz_questions_for_attempt view, which omits
-- is_correct entirely.
CREATE TABLE public.quiz_choices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id uuid NOT NULL REFERENCES public.quiz_questions (id) ON DELETE CASCADE,
  choice_text text NOT NULL,
  is_correct boolean NOT NULL DEFAULT false,
  order_index integer NOT NULL DEFAULT 0
);

CREATE INDEX quiz_choices_question_id_idx ON public.quiz_choices (question_id);

CREATE TABLE public.quiz_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quiz_id uuid NOT NULL REFERENCES public.quizzes (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  answers jsonb NOT NULL,
  score numeric NOT NULL,
  passed boolean NOT NULL,
  hint_level_used smallint NOT NULL DEFAULT 0 CHECK (hint_level_used BETWEEN 0 AND 5),
  submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX quiz_attempts_user_quiz_idx ON public.quiz_attempts (user_id, quiz_id, submitted_at DESC);

-- Client-safe view: never exposes is_correct. Deliberately NOT
-- security_invoker -- it must run as the view owner (postgres) so it can
-- read quiz_questions/quiz_choices (which grant no direct SELECT to
-- authenticated/anon at all, see RLS migration) and simply project
-- is_correct away, rather than requiring the querying role to have its own
-- access to the locked-down base tables.
CREATE VIEW public.quiz_questions_for_attempt
AS
  SELECT
    q.id AS quiz_id, q.slug, q.title, q.passing_score, q.max_attempts,
    q.is_exam, q.time_limit_minutes, q.hint_policy,
    qq.id AS question_id, qq.question_text, qq.question_type, qq.order_index, qq.points,
    qc.id AS choice_id, qc.choice_text, qc.order_index AS choice_order_index
  FROM public.quizzes q
  JOIN public.quiz_questions qq ON qq.quiz_id = q.id
  LEFT JOIN public.quiz_choices qc ON qc.question_id = qq.id
  WHERE q.published = true;

-- ----------------------------------------------------------------------------
-- Labs
-- ----------------------------------------------------------------------------

CREATE TYPE public.lab_category AS ENUM (
  'web', 'api', 'linux', 'windows', 'osint', 'forensics',
  'crypto', 'reverse_engineering', 'cloud', 'container', 'misc'
);
CREATE TYPE public.lab_instance_status AS ENUM ('provisioning', 'running', 'stopped', 'expired', 'destroyed');
CREATE TYPE public.lab_progress_status AS ENUM ('not_started', 'in_progress', 'completed', 'failed');

CREATE TABLE public.labs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  category public.lab_category NOT NULL,
  difficulty public.difficulty_level NOT NULL,
  objectives jsonb NOT NULL DEFAULT '[]'::jsonb,
  environment_spec jsonb NOT NULL DEFAULT '{}'::jsonb,
  estimated_minutes integer NOT NULL DEFAULT 60,
  points integer NOT NULL DEFAULT 100,
  supports_guided boolean NOT NULL DEFAULT true,
  supports_unguided boolean NOT NULL DEFAULT true,
  variant_count integer NOT NULL DEFAULT 1,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.labs.variant_count IS
  'Number of deterministic dynamic variants (section 16). The lab engine '
  'picks variant_seed in [0, variant_count) per lab_instance so usernames/'
  'routes/data differ per attempt while the objective stays identical.';

CREATE TABLE public.lab_skills (
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (lab_id, skill_id)
);

CREATE TABLE public.lab_prerequisites (
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  prerequisite_lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  PRIMARY KEY (lab_id, prerequisite_lab_id),
  CONSTRAINT no_self_prerequisite_lab CHECK (lab_id <> prerequisite_lab_id)
);

CREATE TABLE public.lab_hints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  level smallint NOT NULL CHECK (level BETWEEN 1 AND 5),
  content text NOT NULL,
  point_cost integer NOT NULL DEFAULT 0,
  UNIQUE (lab_id, level)
);

-- Flags are never stored in plaintext. digest(flag, 'sha256') is computed
-- server-side (or by the seed script) before insert.
CREATE TABLE public.lab_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  label text NOT NULL DEFAULT 'flag',
  flag_hash text NOT NULL,
  variant_seed integer NOT NULL DEFAULT 0,
  UNIQUE (lab_id, label, variant_seed)
);

CREATE TABLE public.lab_instances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_id uuid NOT NULL REFERENCES public.labs (id),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  guided boolean NOT NULL DEFAULT true,
  status public.lab_instance_status NOT NULL DEFAULT 'provisioning',
  variant_seed integer NOT NULL DEFAULT 0,
  environment_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  destroyed_at timestamptz
);

CREATE INDEX lab_instances_user_id_idx ON public.lab_instances (user_id);
CREATE INDEX lab_instances_lab_id_idx ON public.lab_instances (lab_id);

CREATE TABLE public.lab_hint_unlocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_instance_id uuid NOT NULL REFERENCES public.lab_instances (id) ON DELETE CASCADE,
  hint_id uuid NOT NULL REFERENCES public.lab_hints (id),
  unlocked_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (lab_instance_id, hint_id)
);

CREATE TABLE public.lab_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_instance_id uuid NOT NULL REFERENCES public.lab_instances (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  flag_id uuid REFERENCES public.lab_flags (id),
  correct boolean NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX lab_submissions_instance_idx ON public.lab_submissions (lab_instance_id, submitted_at DESC);

CREATE TABLE public.lab_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  status public.lab_progress_status NOT NULL DEFAULT 'not_started',
  best_completed_guided boolean,
  attempts integer NOT NULL DEFAULT 0,
  first_completed_at timestamptz,
  last_attempt_at timestamptz,
  UNIQUE (user_id, lab_id)
);

CREATE INDEX lab_progress_user_id_idx ON public.lab_progress (user_id);

-- ----------------------------------------------------------------------------
-- CTF / Arena
-- ----------------------------------------------------------------------------

CREATE TYPE public.ctf_scoring_type AS ENUM ('static', 'dynamic');

CREATE TABLE public.ctf_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  scoring_type public.ctf_scoring_type NOT NULL DEFAULT 'static',
  starts_at timestamptz,
  ends_at timestamptz,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_window CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

CREATE TABLE public.ctf_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid REFERENCES public.ctf_events (id) ON DELETE CASCADE,
  lab_id uuid REFERENCES public.labs (id),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  category public.lab_category NOT NULL,
  difficulty public.difficulty_level NOT NULL,
  points integer NOT NULL DEFAULT 100,
  flag_hash text NOT NULL,
  published boolean NOT NULL DEFAULT false
);

CREATE INDEX ctf_challenges_event_id_idx ON public.ctf_challenges (event_id);

CREATE TABLE public.ctf_challenge_skills (
  challenge_id uuid NOT NULL REFERENCES public.ctf_challenges (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (challenge_id, skill_id)
);

CREATE TABLE public.ctf_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id uuid NOT NULL REFERENCES public.ctf_challenges (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  correct boolean NOT NULL,
  points_awarded integer NOT NULL DEFAULT 0,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ctf_submissions_user_idx ON public.ctf_submissions (user_id, submitted_at DESC);
CREATE INDEX ctf_submissions_challenge_idx ON public.ctf_submissions (challenge_id);

-- Anti-cheat: only one CORRECT submission per user per challenge can ever
-- exist, so a challenge cannot be scored twice. Wrong attempts are
-- unrestricted here (rate-limited by the grading function/API layer
-- instead, see section 32) so genuine trial-and-error keeps working.
CREATE UNIQUE INDEX ctf_submissions_one_correct_per_user
  ON public.ctf_submissions (challenge_id, user_id)
  WHERE correct = true;

-- ----------------------------------------------------------------------------
-- Capstones
-- ----------------------------------------------------------------------------

CREATE TYPE public.capstone_status AS ENUM ('submitted', 'under_review', 'passed', 'needs_revision');

CREATE TABLE public.capstones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  description text,
  report_required boolean NOT NULL DEFAULT true,
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.capstone_skills (
  capstone_id uuid NOT NULL REFERENCES public.capstones (id) ON DELETE CASCADE,
  skill_id uuid NOT NULL REFERENCES public.skills (id) ON DELETE CASCADE,
  PRIMARY KEY (capstone_id, skill_id)
);

CREATE TABLE public.capstone_labs (
  capstone_id uuid NOT NULL REFERENCES public.capstones (id) ON DELETE CASCADE,
  lab_id uuid NOT NULL REFERENCES public.labs (id) ON DELETE CASCADE,
  PRIMARY KEY (capstone_id, lab_id)
);

CREATE TABLE public.capstone_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  capstone_id uuid NOT NULL REFERENCES public.capstones (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  report_content text,
  status public.capstone_status NOT NULL DEFAULT 'submitted',
  reviewer_id uuid REFERENCES auth.users (id),
  reviewer_notes text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz
);

CREATE INDEX capstone_submissions_user_idx ON public.capstone_submissions (user_id);
CREATE INDEX capstone_submissions_capstone_idx ON public.capstone_submissions (capstone_id);

-- ----------------------------------------------------------------------------
-- updated_at triggers
-- ----------------------------------------------------------------------------

CREATE TRIGGER learning_paths_set_updated_at BEFORE UPDATE ON public.learning_paths FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER modules_set_updated_at BEFORE UPDATE ON public.modules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER lessons_set_updated_at BEFORE UPDATE ON public.lessons FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER quizzes_set_updated_at BEFORE UPDATE ON public.quizzes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER labs_set_updated_at BEFORE UPDATE ON public.labs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
