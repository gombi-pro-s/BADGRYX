import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PublishToggle } from "../../../../publish-toggle";
import { toggleLessonPublishedAction } from "../../../actions";
import { EditLessonForm } from "./edit-lesson-form";
import { LessonSkillsForm } from "./lesson-skills-form";

export default async function AdminLessonDetailPage({
  params,
}: {
  params: Promise<{ pathId: string; moduleId: string; lessonId: string }>;
}) {
  const { pathId, moduleId, lessonId } = await params;
  const supabase = await createClient();

  const [{ data: mod }, { data: lesson }, { data: allSkills }, { data: lessonSkills }] = await Promise.all([
    supabase.from("modules").select("id, title").eq("id", moduleId).single(),
    supabase
      .from("lessons")
      .select("id, slug, title, summary, content_markdown, estimated_minutes, published")
      .eq("id", lessonId)
      .single(),
    supabase.from("skills").select("id, name, category_id").order("name"),
    supabase.from("lesson_skills").select("skill_id").eq("lesson_id", lessonId),
  ]);

  if (!mod || !lesson) notFound();

  const selectedSkillIds = new Set((lessonSkills ?? []).map((s) => s.skill_id));

  return (
    <div>
      <Link
        href={`/admin/paths/${pathId}/${moduleId}`}
        className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground"
      >
        &larr; {mod.title}
      </Link>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">{lesson.title}</h2>
        <PublishToggle
          published={lesson.published}
          onToggle={toggleLessonPublishedAction.bind(null, pathId, moduleId, lesson.id)}
        />
      </div>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-4 text-sm font-semibold text-foreground">Lesson content</h3>
        <EditLessonForm
          pathId={pathId}
          moduleId={moduleId}
          lessonId={lesson.id}
          initial={{
            slug: lesson.slug,
            title: lesson.title,
            summary: lesson.summary ?? "",
            content_markdown: lesson.content_markdown,
            estimated_minutes: lesson.estimated_minutes,
          }}
        />
      </div>

      <div className="rounded-lg border border-border bg-surface p-6">
        <h3 className="mb-1 text-sm font-semibold text-foreground">Skills taught</h3>
        <p className="mb-4 text-xs text-foreground-subtle">
          Feeds the Skill Graph: a comprehension-check quiz tied to the same skill(s) is what
          actually records &quot;theory&quot; evidence, not just reading this lesson.
        </p>
        <LessonSkillsForm
          pathId={pathId}
          moduleId={moduleId}
          lessonId={lesson.id}
          allSkills={allSkills ?? []}
          selectedSkillIds={[...selectedSkillIds]}
        />
      </div>
    </div>
  );
}
