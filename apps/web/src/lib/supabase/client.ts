"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/types/database";
import { getSupabaseAnonKey, getSupabaseUrl } from "./env";

/**
 * Browser Supabase client. Uses only the public URL + anon key -- the anon
 * key is safe to ship to the client because every table it can reach is
 * gated by Row Level Security (see supabase/migrations). Never import
 * lib/supabase/admin.ts (the service_role client) from client code.
 */
export function createClient() {
  return createBrowserClient<Database>(getSupabaseUrl(), getSupabaseAnonKey());
}
