import { afterEach, describe, expect, it, vi } from "vitest";
import { getSupabaseAnonKey, getSupabaseServiceRoleKey, getSupabaseUrl } from "../env";

describe("supabase env helpers", () => {
  const original = { ...process.env };

  afterEach(() => {
    process.env = { ...original };
    vi.unstubAllGlobals();
  });

  it("throws a clear error when NEXT_PUBLIC_SUPABASE_URL is missing", () => {
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    expect(() => getSupabaseUrl()).toThrow(/NEXT_PUBLIC_SUPABASE_URL/);
  });

  it("returns the URL when set", () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
    expect(getSupabaseUrl()).toBe("https://example.supabase.co");
  });

  it("throws when NEXT_PUBLIC_SUPABASE_ANON_KEY is missing", () => {
    delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    expect(() => getSupabaseAnonKey()).toThrow(/NEXT_PUBLIC_SUPABASE_ANON_KEY/);
  });

  it("refuses to return the service role key in a browser context", () => {
    process.env.SUPABASE_SERVICE_ROLE_KEY = "secret-value";
    vi.stubGlobal("window", {});
    expect(() => getSupabaseServiceRoleKey()).toThrow(/browser context/);
  });

  it("returns the service role key in a server context", () => {
    process.env.SUPABASE_SERVICE_ROLE_KEY = "secret-value";
    // The jsdom test environment provides a global `window` by default;
    // explicitly undefine it here to simulate a real Node.js server context.
    vi.stubGlobal("window", undefined);
    expect(getSupabaseServiceRoleKey()).toBe("secret-value");
  });
});
