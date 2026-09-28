import { describe, expect, it } from "vitest";
import { pickAnnouncementText } from "../announcement-translation";

const base = { title: "New CTF event live", body_markdown: "Details..." };

describe("pickAnnouncementText", () => {
  it("returns the base text for the default locale, even if a translation row exists", () => {
    const translations = [{ locale: "es", title: "Nuevo evento CTF en vivo", body_markdown: "Detalles..." }];
    expect(pickAnnouncementText(base, translations, "en")).toEqual(base);
  });

  it("returns the matching translation for a non-default locale", () => {
    const translations = [{ locale: "es", title: "Nuevo evento CTF en vivo", body_markdown: "Detalles..." }];
    expect(pickAnnouncementText(base, translations, "es")).toEqual({
      title: "Nuevo evento CTF en vivo",
      body_markdown: "Detalles...",
    });
  });

  it("falls back to the base text when no translation exists for that locale", () => {
    expect(pickAnnouncementText(base, [], "es")).toEqual(base);
  });

  it("falls back to the base text when translations exist for other announcements/locales only", () => {
    const translations = [{ locale: "fr", title: "Autre langue", body_markdown: "Autre" }];
    expect(pickAnnouncementText(base, translations, "es")).toEqual(base);
  });
});
