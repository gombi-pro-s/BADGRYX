import { describe, expect, it } from "vitest";
import { emailSchema, passwordSchema } from "../validation";

describe("emailSchema", () => {
  it("accepts a valid email", () => {
    expect(emailSchema.safeParse("alice@example.com").success).toBe(true);
  });

  it.each(["", "not-an-email", "alice@", "@example.com", "alice example.com"])(
    "rejects invalid email %s",
    (value) => {
      expect(emailSchema.safeParse(value).success).toBe(false);
    },
  );
});

describe("passwordSchema", () => {
  it("accepts a strong password", () => {
    expect(passwordSchema.safeParse("Str0ngPassword!").success).toBe(true);
  });

  it("rejects a password shorter than 12 characters", () => {
    const result = passwordSchema.safeParse("Sh0rtPw");
    expect(result.success).toBe(false);
  });

  it("rejects a password with no uppercase letter", () => {
    const result = passwordSchema.safeParse("lowercase123456");
    expect(result.success).toBe(false);
  });

  it("rejects a password with no lowercase letter", () => {
    const result = passwordSchema.safeParse("UPPERCASE123456");
    expect(result.success).toBe(false);
  });

  it("rejects a password with no digit", () => {
    const result = passwordSchema.safeParse("NoDigitsHereAtAll");
    expect(result.success).toBe(false);
  });

  it("rejects common weak passwords that happen to be long enough", () => {
    // "password" repeated is 16 chars but still fails the character-class
    // requirements -- length alone must never be sufficient.
    const result = passwordSchema.safeParse("passwordpassword");
    expect(result.success).toBe(false);
  });
});
