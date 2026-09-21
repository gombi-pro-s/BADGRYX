import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/types/database";
import { getSupabaseAnonKey, getSupabaseUrl } from "./env";

/**
 * Server Supabase client for Server Components, Server Actions, and Route
 * Handlers. Reads the user's session from cookies and runs every query
 * under that user's RLS context (via the anon key + their JWT) -- this is
 * NOT the service_role client. Cookie writes are a no-op when called from a
 * Server Component (Next.js forbids it there); the session refresh itself
 * happens in middleware.ts, which *can* write cookies.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(getSupabaseUrl(), getSupabaseAnonKey(), {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Called from a Server Component render -- ignore. Session
          // refresh cookies are written by middleware.ts instead.
        }
      },
    },
  });
}
