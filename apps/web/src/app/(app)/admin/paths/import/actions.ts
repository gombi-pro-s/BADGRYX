"use server";

import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { importPathBundle } from "@/lib/content-io/import-path-bundle";

export interface ImportFormState {
  error: string | null;
  importedPathId: string | null;
  importedSlug: string | null;
  warnings: string[];
}

export const initialImportState: ImportFormState = {
  error: null,
  importedPathId: null,
  importedSlug: null,
  warnings: [],
};

/**
 * Imports a learning-path bundle (see lib/content-io/path-bundle.ts) as a
 * new learning path. The actual multi-step insert-with-manual-rollback
 * orchestration lives in `importPathBundle()`
 * (lib/content-io/import-path-bundle.ts), shared with the mobile-facing
 * `/api/admin/paths/import` Route Handler -- this action is just the
 * FormData adapter around it. See ADR 0058.
 */
export async function importPathBundleAction(
  _prev: ImportFormState,
  formData: FormData,
): Promise<ImportFormState> {
  const admin = await requireAdmin();
  const raw = String(formData.get("bundle") ?? "");
  if (!raw.trim()) {
    return { ...initialImportState, error: "Paste or choose a bundle JSON file first." };
  }

  const supabase = await createClient();
  const result = await importPathBundle(supabase, admin.id, raw);
  if (result.error) {
    return { ...initialImportState, error: result.error };
  }

  revalidatePath("/admin/paths");
  return { error: null, importedPathId: result.importedPathId, importedSlug: result.importedSlug, warnings: result.warnings };
}
