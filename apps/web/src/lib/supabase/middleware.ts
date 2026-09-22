import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import type { Database } from "@/types/database";
import { getSupabaseAnonKey, getSupabaseUrl } from "./env";

const PROTECTED_PREFIXES = [
  "/dashboard",
  "/skills",
  "/settings",
  "/admin",
  "/instructor",
  "/learn",
  "/labs",
  "/ctf",
  "/capstones",
  "/mentor",
  "/scanner",
  "/investigate",
  "/orgs",
];
const ADMIN_ONLY_PREFIXES = ["/admin"];

/**
 * Refreshes the Supabase auth session on every request (required by
 * @supabase/ssr -- the session cookie is short-lived and must be renewed
 * server-side) and enforces the auth wall for protected routes.
 *
 * This is UX-level route protection only. Every protected Server
 * Component/Action/Route Handler must ALSO call requireUser()/requireRole()
 * itself (see lib/auth/session.ts) -- middleware redirecting an
 * unauthenticated browser is not a substitute for RLS + server-side checks,
 * which are what actually enforce authorization (section 27/40).
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient<Database>(getSupabaseUrl(), getSupabaseAnonKey(), {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const path = request.nextUrl.pathname;
  const isProtected = PROTECTED_PREFIXES.some((p) => path.startsWith(p));

  if (isProtected && !user) {
    const redirectUrl = new URL("/login", request.url);
    redirectUrl.searchParams.set("next", path);
    return NextResponse.redirect(redirectUrl);
  }

  if (ADMIN_ONLY_PREFIXES.some((p) => path.startsWith(p)) && user) {
    const { data: roles } = await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id);
    const isAdmin = roles?.some((r) => r.role === "admin") ?? false;
    if (!isAdmin) {
      return NextResponse.redirect(new URL("/dashboard", request.url));
    }
  }

  return response;
}
