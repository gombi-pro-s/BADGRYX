import { describe, expect, it } from "vitest";
import { DEFAULT_LOCALE, isSupportedLocale, SUPPORTED_LOCALES } from "../locales";

describe("isSupportedLocale", () => {
  it("accepts every locale in SUPPORTED_LOCALES", () => {
    for (const locale of SUPPORTED_LOCALES) {
      expect(isSupportedLocale(locale)).toBe(true);
    }
  });

  it("rejects an unsupported locale string", () => {
    expect(isSupportedLocale("fr")).toBe(false);
    expect(isSupportedLocale("")).toBe(false);
    expect(isSupportedLocale("EN")).toBe(false);
  });

  it("DEFAULT_LOCALE is itself a supported locale", () => {
    expect(isSupportedLocale(DEFAULT_LOCALE)).toBe(true);
  });
});
