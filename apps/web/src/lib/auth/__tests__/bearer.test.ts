import { describe, expect, it } from "vitest";
import { extractBearerToken } from "../bearer";

describe("extractBearerToken", () => {
  it("extracts the token from a real Authorization header", () => {
    expect(extractBearerToken("Bearer abc.def.ghi")).toBe("abc.def.ghi");
  });

  it("is case-insensitive on the Bearer scheme", () => {
    expect(extractBearerToken("bearer abc.def.ghi")).toBe("abc.def.ghi");
  });

  it("returns null when the header is missing", () => {
    expect(extractBearerToken(null)).toBeNull();
  });

  it("returns null for a different auth scheme", () => {
    expect(extractBearerToken("Basic dXNlcjpwYXNz")).toBeNull();
  });

  it("returns null for a Bearer header with no token", () => {
    expect(extractBearerToken("Bearer")).toBeNull();
    expect(extractBearerToken("Bearer   ")).toBeNull();
  });

  it("returns null for an empty string", () => {
    expect(extractBearerToken("")).toBeNull();
  });

  it("trims surrounding whitespace around the header and the token", () => {
    expect(extractBearerToken("  Bearer   abc.def.ghi  ")).toBe("abc.def.ghi");
  });
});
