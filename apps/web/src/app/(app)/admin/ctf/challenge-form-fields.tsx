import { Input, Label } from "@/components/ui/input";
import type { DifficultyLevel, LabCategory } from "@/types/database";

const CATEGORIES: LabCategory[] = [
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
  description?: string;
  category?: LabCategory;
  difficulty?: DifficultyLevel;
  points?: number;
}

export function ChallengeFormFields({
  initial = {},
  flagOptional = false,
}: {
  initial?: Initial;
  flagOptional?: boolean;
}) {
  return (
    <>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <Label htmlFor="title">Title</Label>
          <Input id="title" name="title" defaultValue={initial.title} required maxLength={200} />
        </div>
        <div>
          <Label htmlFor="slug">Slug</Label>
          <Input id="slug" name="slug" defaultValue={initial.slug} required pattern="[a-z0-9-]{3,64}" placeholder="web-sqli-1" />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-3">
        <div>
          <Label htmlFor="category">Category</Label>
          <select id="category" name="category" defaultValue={initial.category ?? "web"} className={selectClasses()}>
            {CATEGORIES.map((c) => (
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
        <div>
          <Label htmlFor="points">Points</Label>
          <Input id="points" name="points" type="number" min={0} max={10000} defaultValue={initial.points ?? 100} required />
        </div>
      </div>
      <div>
        <Label htmlFor="description">Description</Label>
        <textarea
          id="description"
          name="description"
          defaultValue={initial.description}
          rows={4}
          maxLength={4000}
          className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
        />
      </div>
      <div>
        <Label htmlFor="plaintext">Flag (plaintext, hashed on submit)</Label>
        <Input
          id="plaintext"
          name="plaintext"
          required={!flagOptional}
          minLength={4}
          maxLength={500}
          autoComplete="off"
          placeholder={flagOptional ? "Leave blank to keep the current flag" : undefined}
        />
        <p className="mt-1.5 text-xs text-foreground-subtle">
          Hashed (SHA-256) the moment you submit. Never stored or shown as plaintext again.
        </p>
      </div>
    </>
  );
}
