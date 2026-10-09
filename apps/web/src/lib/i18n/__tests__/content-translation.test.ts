import { describe, expect, it } from "vitest";
import { pickLessonText, pickPathText } from "../content-translation";

const basePath = { title: "SQL Injection", description: "Learn SQLi." };
const baseLesson = { title: "What is SQLi?", content_markdown: "Body text." };

describe("pickPathText", () => {
  it("returns the base text for the default locale, even if a translation row exists", () => {
    const translations = [{ locale: "es", title: "Inyección SQL", description: "Aprende SQLi." }];
    expect(pickPathText(basePath, translations, "en")).toEqual(basePath);
  });

  it("returns the matching translation for a non-default locale", () => {
    const translations = [{ locale: "es", title: "Inyección SQL", description: "Aprende SQLi." }];
    expect(pickPathText(basePath, translations, "es")).toEqual({
      title: "Inyección SQL",
      description: "Aprende SQLi.",
    });
  });

  it("falls back to the base text when no translation exists for that locale", () => {
    expect(pickPathText(basePath, [], "es")).toEqual(basePath);
  });

  it("falls back to the base text when translations exist for other locales only", () => {
    const translations = [{ locale: "fr", title: "Autre langue", description: "Autre" }];
    expect(pickPathText(basePath, translations, "es")).toEqual(basePath);
  });
});

describe("pickLessonText", () => {
  it("returns the base text for the default locale, even if a translation row exists", () => {
    const translations = [{ locale: "es", title: "¿Qué es la inyección SQL?", content_markdown: "Texto." }];
    expect(pickLessonText(baseLesson, translations, "en")).toEqual(baseLesson);
  });

  it("returns the matching translation for a non-default locale", () => {
    const translations = [{ locale: "es", title: "¿Qué es la inyección SQL?", content_markdown: "Texto." }];
    expect(pickLessonText(baseLesson, translations, "es")).toEqual({
      title: "¿Qué es la inyección SQL?",
      content_markdown: "Texto.",
    });
  });

  it("falls back to the base text when no translation exists for that locale", () => {
    expect(pickLessonText(baseLesson, [], "es")).toEqual(baseLesson);
  });
});
