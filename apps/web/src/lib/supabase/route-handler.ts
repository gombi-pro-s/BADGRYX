import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/types/database";
import { getSupabaseAnonKey, getSupabaseUrl } from "./env";

/**
 * A Supabase client for Route Handlers that a non-browser client (the
 * Flutter app) may call directly, alongside apps/web's own browser
 * fetches. Behaves exactly like lib/supabase/server.ts's createClient()
 * (cookie session, anon key, real RLS) when no bearer token is passed;
 * when one is, every Postgrest/RPC request from this client instance
 * carries it as its Authorization header, so `auth.uid()` resolves to
 * that token's user and RLS enforces against them -- the same security
 * boundary either caller gets, never a service_role bypass.
 */
export async function createRouteHandlerClient(bearerToken?: string | null) {
  const cookieStore = await cookies();

  return createServerClient<Database>(getSupabaseUrl(), getSupabaseAnonKey(), {
    global: bearerToken ? { headers: { Authorization: `Bearer ${bearerToken}` } } : undefined,
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
          // Called from a Server Component render -- ignore, same as
          // lib/supabase/server.ts.
        }
      },
    },
  });
}
