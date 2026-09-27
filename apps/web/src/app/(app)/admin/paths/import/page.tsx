import type { Metadata } from "next";
import Link from "next/link";
import { ImportPathForm } from "./import-form";

export const metadata: Metadata = { title: "Import Learning Path" };

export default function AdminPathImportPage() {
  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h2 className="text-lg font-semibold text-foreground">Import a learning path</h2>
        <Link href="/admin/paths" className="text-sm text-foreground-muted hover:underline">
          Back to paths
        </Link>
      </div>

      <p className="mb-6 text-sm text-foreground-muted">
        Paste or upload a bundle exported from another path (via the &ldquo;Export&rdquo; link on a
        path&rsquo;s detail page). This always creates a new path - it never merges into or overwrites
        an existing one. If any step fails, nothing is left behind: the whole import is rolled back.
      </p>

      <div className="rounded-lg border border-border bg-surface p-6">
        <ImportPathForm />
      </div>
    </div>
  );
}
