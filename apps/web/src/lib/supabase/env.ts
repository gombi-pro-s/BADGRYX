/**
 * Central place that reads and validates Supabase environment variables, so
 * a missing/misconfigured env var fails fast with a clear message instead of
 * surfacing as a confusing runtime error deep in a Supabase client call.
 */

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required environment variable ${name}. See .env.example / MANUAL_SETUP.md.`,
    );
  }
  return value;
}

export function getSupabaseUrl(): string {
  return requireEnv("NEXT_PUBLIC_SUPABASE_URL");
}

export function getSupabaseAnonKey(): string {
  return requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
}

/** Server-only. Never import this from a Client Component. */
export function getSupabaseServiceRoleKey(): string {
  if (typeof window !== "undefined") {
    throw new Error(
      "getSupabaseServiceRoleKey() was called in a browser context. The service_role key " +
        "bypasses Row Level Security and must never reach the client.",
    );
  }
  return requireEnv("SUPABASE_SERVICE_ROLE_KEY");
}
