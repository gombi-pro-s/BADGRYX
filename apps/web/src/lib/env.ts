import "server-only";

/**
 * Server-only environment variables that aren't Supabase-specific (see
 * lib/supabase/env.ts for those). Guarded by `server-only` the same way --
 * importing this into a Client Component is a build-time error, not a
 * runtime secret leak.
 */
export function getAnthropicApiKey(): string {
  const value = process.env.ANTHROPIC_API_KEY;
  if (!value) {
    throw new Error("Missing required environment variable ANTHROPIC_API_KEY. See .env.example / MANUAL_SETUP.md.");
  }
  return value;
}
