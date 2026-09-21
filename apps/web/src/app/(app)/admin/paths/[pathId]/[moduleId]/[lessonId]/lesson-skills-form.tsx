"use client";

import { SkillTagger } from "../../../../skill-tagger";
import { setLessonSkillsAction } from "../../../actions";

interface Skill {
  id: string;
  name: string;
}

export function LessonSkillsForm({
  pathId,
  moduleId,
  lessonId,
  allSkills,
  selectedSkillIds,
}: {
  pathId: string;
  moduleId: string;
  lessonId: string;
  allSkills: Skill[];
  selectedSkillIds: string[];
}) {
  return (
    <SkillTagger
      allSkills={allSkills}
      selectedSkillIds={selectedSkillIds}
      onSave={(skillIds) => setLessonSkillsAction(pathId, moduleId, lessonId, skillIds)}
    />
  );
}
