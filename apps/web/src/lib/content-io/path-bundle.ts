// Pure validation for the learning-path export/import JSON format. No I/O:
// this only describes the shape and gets exercised directly in unit tests.
// The DB read (export) and DB write (import) live in the admin route/action
// that use this schema, mirroring the existing "pure logic vs server-only
// I/O" split (lib/mentor/prompt.ts vs client.ts, lib/turnstile/turnstile.ts
// vs turnstile-client.ts).
import { z } from "zod";
import type { HintPolicy, QuestionType } from "@/types/database";

export const PATH_BUNDLE_FORMAT = "icorepen.learning_path.v1" as const;

const HINT_POLICIES: HintPolicy[] = ["none", "limited", "full"];
const QUESTION_TYPES: QuestionType[] = ["single_choice", "multi_choice", "true_false", "short_answer"];

const slugSchema = z
  .string()
  .trim()
  .regex(/^[a-z0-9-]{3,64}$/, "Lowercase letters, numbers, and hyphens only (3-64 chars).");

const choiceSchema = z.object({
  choice_text: z.string().trim().min(1).max(2000),
  is_correct: z.boolean().default(false),
});

const questionSchema = z
  .object({
    question_text: z.string().trim().min(1),
    question_type: z.enum(QUESTION_TYPES as [QuestionType, ...QuestionType[]]).default("single_choice"),
    points: z.number().min(0).max(1000).default(1),
    choices: z.array(choiceSchema).min(2, "Each question needs at least two choices."),
  })
  .refine((q) => q.choices.some((c) => c.is_correct), {
    message: "Each question needs at least one correct choice.",
    path: ["choices"],
  });

const quizSchema = z.object({
  slug: slugSchema,
  title: z.string().trim().min(1).max(200),
  passing_score: z.number().min(0).max(100).default(70),
  max_attempts: z.number().int().min(1).max(100).optional(),
  is_exam: z.boolean().default(false),
  time_limit_minutes: z.number().int().min(1).max(600).optional(),
  hint_policy: z.enum(HINT_POLICIES as [HintPolicy, ...HintPolicy[]]).default("full"),
  published: z.boolean().default(false),
  skill_slugs: z.array(z.string()).default([]),
  questions: z.array(questionSchema).default([]),
});

const lessonSchema = z.object({
  slug: slugSchema,
  title: z.string().trim().min(1).max(200),
  summary: z.string().trim().max(500).optional(),
  content_markdown: z.string().min(1, "Lesson content is required."),
  estimated_minutes: z.number().int().min(1).max(600).default(10),
  published: z.boolean().default(false),
  skill_slugs: z.array(z.string()).default([]),
  quiz: quizSchema.optional(),
});

const moduleSchema = z.object({
  slug: slugSchema,
  title: z.string().trim().min(1).max(200),
  description: z.string().trim().max(2000).optional(),
  published: z.boolean().default(false),
  lessons: z.array(lessonSchema).default([]),
});

export const pathBundleSchema = z.object({
  format: z.literal(PATH_BUNDLE_FORMAT),
  path: z.object({
    slug: slugSchema,
    title: z.string().trim().min(1).max(200),
    description: z.string().trim().max(2000).optional(),
    cover_image_url: z.string().trim().url().max(2000).optional(),
    published: z.boolean().default(false),
  }),
  modules: z.array(moduleSchema).default([]),
});

export type PathBundle = z.infer<typeof pathBundleSchema>;
export type ModuleBundle = z.infer<typeof moduleSchema>;
export type LessonBundle = z.infer<typeof lessonSchema>;
export type QuizBundle = z.infer<typeof quizSchema>;
export type QuestionBundle = z.infer<typeof questionSchema>;

/** Parses and validates raw JSON text, returning a single readable error message on failure. */
export function parsePathBundle(raw: string): { data: PathBundle; error: null } | { data: null; error: string } {
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return { data: null, error: "That isn't valid JSON." };
  }

  if (typeof json === "object" && json !== null && (json as Record<string, unknown>).format !== PATH_BUNDLE_FORMAT) {
    return {
      data: null,
      error: `Unrecognized format. Expected "format": "${PATH_BUNDLE_FORMAT}".`,
    };
  }

  const parsed = pathBundleSchema.safeParse(json);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const where = issue.path.length > 0 ? ` (at ${issue.path.join(".")})` : "";
    return { data: null, error: `${issue.message}${where}` };
  }
  return { data: parsed.data, error: null };
}
