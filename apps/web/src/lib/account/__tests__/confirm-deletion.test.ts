import { describe, expect, test } from "vitest";
import { confirmsAccountDeletion } from "../confirm-deletion";

describe("confirmsAccountDeletion", () => {
  test("matches the exact email", () => {
    expect(confirmsAccountDeletion("user@example.com", "user@example.com")).toBe(true);
  });

  test("is case-insensitive", () => {
    expect(confirmsAccountDeletion("USER@EXAMPLE.COM", "user@example.com")).toBe(true);
  });

  test("ignores leading/trailing whitespace in the typed confirmation", () => {
    expect(confirmsAccountDeletion("  user@example.com  ", "user@example.com")).toBe(true);
  });

  test("rejects a mismatched email", () => {
    expect(confirmsAccountDeletion("someone-else@example.com", "user@example.com")).toBe(false);
  });

  test("rejects an empty confirmation", () => {
    expect(confirmsAccountDeletion("", "user@example.com")).toBe(false);
  });

  test("rejects when the account has no email at all", () => {
    expect(confirmsAccountDeletion("user@example.com", null)).toBe(false);
    expect(confirmsAccountDeletion("user@example.com", undefined)).toBe(false);
  });
});
