import { revalidatePath } from "next/cache";
import { NextResponse } from "next/server";
import { z } from "zod";
import { requireApiUser } from "@/lib/auth/api";
import { importPathBundle } from "@/lib/content-io/import-path-bundle";

const bodySchema = z.object({
  bundle: z.string().trim().min(1, "Paste or choose a bundle JSON file first."),
});

/**
 * The mobile equivalent of `admin/paths/import/actions.ts`'s
 * `importPathBundleAction` -- a Server Action can't be called directly by
 * a non-Next HTTP client, so this Route Handler exists purely as a JSON
 * adapter around the exact same `importPathBundle()` (see
 * `lib/content-io/import-path-bundle.ts`), never a second implementation
 * of that multi-step insert-with-rollback orchestration. See ADR 0058.
 */
export async function POST(request: Request) {
  const auth = await requireApiUser(request);
  if ("unauthorized" in auth) return auth.unauthorized;
  const { user, supabase } = auth;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Request body must be JSON." }, { status: 400 });
  }

  const parsedBody = bodySchema.safeParse(body);
  if (!parsedBody.success) {
    return NextResponse.json({ error: parsedBody.error.issues[0]?.message ?? "Invalid input." }, { status: 400 });
  }

  const result = await importPathBundle(supabase, user.id, parsedBody.data.bundle);
  if (result.error) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }

  revalidatePath("/admin/paths");
  return NextResponse.json({
    importedPathId: result.importedPathId,
    importedSlug: result.importedSlug,
    warnings: result.warnings,
  });
}
