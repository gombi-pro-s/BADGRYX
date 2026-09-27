import { describe, expect, it } from "vitest";
import { translate, type MessageKey } from "../translate";
import { en } from "../messages/en";
import { es } from "../messages/es";

describe("translate", () => {
  it("returns the English string for the 'en' locale", () => {
    expect(translate("en", "landing.cta.startLearning")).toBe("Start learning");
  });

  it("returns the real Spanish translation for the 'es' locale when one exists", () => {
    expect(translate("es", "landing.cta.startLearning")).toBe("Empezar a aprender");
  });

  it("falls back to English when the target locale's dictionary is missing a key", () => {
    // The real Spanish dictionary is complete right now, so this exercises
    // the fallback branch directly by removing one entry at runtime for
    // the duration of the assertion, then restoring it -- proving the
    // fallback code path works without leaving the real dictionary
    // incomplete afterward.
    const key: MessageKey = "landing.nav.dashboard";
    const original = es[key];
    delete es[key];
    try {
      expect(translate("es", key)).toBe(en[key]);
    } finally {
      es[key] = original;
    }
  });

  it("interpolates a {param} placeholder found in the resolved template", () => {
    const key: MessageKey = "landing.nav.dashboard";
    const original = en[key];
    (en as Record<string, string>)[key] = "Hello {name}, you have {count} messages";
    try {
      expect(translate("en", key, { name: "Alice", count: 3 })).toBe("Hello Alice, you have 3 messages");
    } finally {
      (en as Record<string, string>)[key] = original;
    }
  });

  it("leaves an unresolved placeholder untouched when its param isn't provided", () => {
    const key: MessageKey = "landing.nav.dashboard";
    const original = en[key];
    (en as Record<string, string>)[key] = "Hello {name}";
    try {
      expect(translate("en", key, { other: "x" })).toBe("Hello {name}");
    } finally {
      (en as Record<string, string>)[key] = original;
    }
  });

  it("returns the plain resolved string unchanged when no params are passed", () => {
    expect(translate("en", "landing.cta.login")).toBe("Log in");
  });

  it("every real key in the Spanish dictionary has a non-empty translation", () => {
    for (const [key, value] of Object.entries(es)) {
      expect(value, `es["${key}"] should not be empty`).not.toBe("");
    }
  });
});
