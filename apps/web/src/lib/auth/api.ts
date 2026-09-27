import "server-only";

import { NextResponse } from "next/server";
import type { User, SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { createRouteHandlerClient } from "@/lib/supabase/route-handler";
import { extractBearerToken } from "./bearer";

export interface ApiAuthResult {
  user: User;
  supabase: SupabaseClient<Database>;
}

/**
 * The Route Handler equivalent of requireUser() (lib/auth/session.ts),
 * for endpoints a non-browser client (mobile/app) calls directly rather
 * than through a browser's cookie jar -- returns a real 401 JSON body
 * instead of requireUser()'s redirect("/login"), which would otherwise
 * turn into a confusing redirect response for an API caller with no
 * browser to follow it.
 *
 * Accepts EITHER an `Authorization: Bearer <access_token>` header (the
 * mobile app's session, from supabase_flutter) OR the existing cookie
 * session (apps/web's own fetches keep working unchanged, since they
 * never send that header and this falls through to the cookie path).
 * Whichever path resolves the user, the returned `supabase` client is
 * still anon-key + that user's own JWT -- RLS is the only real boundary
 * either caller gets, exactly like every other client in this app.
 */
export async function requireApiUser(request: Request): Promise<ApiAuthResult | { unauthorized: NextResponse }> {
  const token = extractBearerToken(request.headers.get("Authorization"));
  const supabase = await createRouteHandlerClient(token);

  const {
    data: { user },
  } = token ? await supabase.auth.getUser(token) : await supabase.auth.getUser();

  if (!user) {
    return { unauthorized: NextResponse.json({ error: "Unauthorized" }, { status: 401 }) };
  }
  return { user, supabase };
}
