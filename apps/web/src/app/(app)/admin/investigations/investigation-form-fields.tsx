import { Input, Label } from "@/components/ui/input";
import type { DifficultyLevel, LabCategory } from "@/types/database";

const LAB_CATEGORIES: LabCategory[] = [
  "web",
  "api",
  "linux",
  "windows",
  "osint",
  "forensics",
  "crypto",
  "reverse_engineering",
  "cloud",
  "container",
  "misc",
];
const DIFFICULTIES: DifficultyLevel[] = ["beginner", "easy", "medium", "hard", "insane"];

function selectClasses() {
  return "h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent";
}

interface Initial {
  slug?: string;
  title?: string;
  briefing?: string;
  category?: LabCategory;
  difficulty?: DifficultyLevel;
  estimated_minutes?: number;
  points?: number;
  passing_score?: number;
}

export function InvestigationFormFields({ initial = {} }: { initial?: Initial }) {
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="slug">Slug</Label>
          <Input id="slug" name="slug" defaultValue={initial.slug} required pattern="[a-z0-9-]{3,64}" placeholder="phishing-campaign-101" />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="category">Category</Label>
          <select id="category" name="category" defaultValue={initial.category ?? "osint"} className={selectClasses()}>
            {LAB_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>
        <div>
          <Label htmlFor="difficulty">Difficulty</Label>
          <select id="difficulty" name="difficulty" defaultValue={initial.difficulty ?? "easy"} className={selectClasses()}>
            {DIFFICULTIES.map((d) => (
              <option key={d} value={d}>
                {d}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-3">
        <div>
          <Label htmlFor="estimated_minutes">Estimated minutes</Label>
          <Input
            id="estimated_minutes"
            name="estimated_minutes"
            type="number"
            min={1}
            max={600}
            defaultValue={initial.estimated_minutes ?? 45}
            required
          />
        </div>
        <div>
          <Label htmlFor="points">Points</Label>
          <Input id="points" name="points" type="number" min={0} max={10000} defaultValue={initial.points ?? 100} required />
        </div>
        <div>
          <Label htmlFor="passing_score">Passing score (%)</Label>
          <Input
            id="passing_score"
            name="passing_score"
            type="number"
            min={0}
            max={100}
            defaultValue={initial.passing_score ?? 70}
            required
          />
        </div>
      </div>
      <div>
        <Label htmlFor="briefing">Case briefing (markdown)</Label>
        <textarea
          id="briefing"
          name="briefing"
          defaultValue={initial.briefing}
          rows={6}
          maxLength={8000}
          placeholder="Frame the scenario: what happened, what the investigator needs to figure out."
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
    </>
  );
}
