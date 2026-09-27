import { describe, expect, it } from "vitest";
import { PATH_BUNDLE_FORMAT, parsePathBundle } from "../path-bundle";

function validBundle() {
  return {
    format: PATH_BUNDLE_FORMAT,
    path: { slug: "web-app-security", title: "Web App Security" },
    modules: [
      {
        slug: "sql-injection",
        title: "SQL Injection",
        lessons: [
          {
            slug: "intro-to-sqli",
            title: "Intro to SQLi",
            content_markdown: "# SQLi\n\nBody text.",
            skill_slugs: ["sql-injection-basics"],
            quiz: {
              slug: "intro-to-sqli-quiz",
              title: "Intro to SQLi Quiz",
              questions: [
                {
                  question_text: "What is SQLi?",
                  choices: [
                    { choice_text: "An injection flaw", is_correct: true },
                    { choice_text: "A CSS bug", is_correct: false },
                  ],
                },
              ],
            },
          },
        ],
      },
    ],
  };
}

describe("parsePathBundle", () => {
  it("accepts a well-formed bundle and fills in defaults", () => {
    const result = parsePathBundle(JSON.stringify(validBundle()));
    expect(result.error).toBeNull();
    expect(result.data?.path.slug).toBe("web-app-security");
    expect(result.data?.modules[0].lessons[0].quiz?.questions[0].points).toBe(1);
    expect(result.data?.modules[0].published).toBe(false);
  });

  it("rejects invalid JSON", () => {
    const result = parsePathBundle("{not json");
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/valid JSON/);
  });

  it("rejects a bundle with the wrong format tag", () => {
    const bundle = validBundle();
    (bundle as { format: string }).format = "some.other.format";
    const result = parsePathBundle(JSON.stringify(bundle));
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/Unrecognized format/);
  });

  it("rejects a bundle missing the format tag entirely", () => {
    const bundle: Record<string, unknown> = validBundle();
    delete bundle.format;
    const result = parsePathBundle(JSON.stringify(bundle));
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/Unrecognized format/);
  });

  it("rejects a path slug that doesn't match the slug pattern", () => {
    const bundle = validBundle();
    bundle.path.slug = "Not A Valid Slug!";
    const result = parsePathBundle(JSON.stringify(bundle));
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/Lowercase letters/);
  });

  it("rejects a question with fewer than two choices", () => {
    const bundle = validBundle();
    bundle.modules[0].lessons[0].quiz!.questions[0].choices = [{ choice_text: "Only one", is_correct: true }];
    const result = parsePathBundle(JSON.stringify(bundle));
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/at least two choices/);
  });

  it("rejects a question with no correct choice", () => {
    const bundle = validBundle();
    bundle.modules[0].lessons[0].quiz!.questions[0].choices = [
      { choice_text: "A", is_correct: false },
      { choice_text: "B", is_correct: false },
    ];
    const result = parsePathBundle(JSON.stringify(bundle));
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/at least one correct choice/);
  });

  it("accepts a bundle with no modules at all", () => {
    const result = parsePathBundle(JSON.stringify({ format: PATH_BUNDLE_FORMAT, path: { slug: "empty-path", title: "Empty" } }));
    expect(result.error).toBeNull();
    expect(result.data?.modules).toEqual([]);
  });

  it("rejects an empty lesson content_markdown", () => {
    const bundle = validBundle();
    bundle.modules[0].lessons[0].content_markdown = "";
    const result = parsePathBundle(JSON.stringify(bundle));
    expect(result.data).toBeNull();
    expect(result.error).toMatch(/content is required/);
  });
});
