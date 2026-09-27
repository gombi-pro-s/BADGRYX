import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { CreateReportForm } from "./create-report-form";

export const metadata: Metadata = { title: "Reports" };

const KIND_LABELS: Record<string, string> = {
  pentest_report: "Pentest report",
  methodology: "Methodology write-up",
};

export default async function ReportsPage() {
  const user = await requireUser();
  const supabase = await createClient();

  const { data: reports } = await supabase
    .from("reports")
    .select("id, title, kind, updated_at")
    .eq("user_id", user.id)
    .order("updated_at", { ascending: false });

  return (
    <div className="mx-auto max-w-3xl px-6 py-10">
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Reports</h1>
      <p className="mb-6 text-sm text-foreground-muted">
        Write a pentest report or a methodology write-up and ask the AI Mentor to critique it -- structure,
        evidence, gaps in reasoning. This is practice, reviewed by the Mentor only; it&apos;s separate from a
        capstone&apos;s reviewed submission and never affects your Skill Graph.
      </p>

      {reports && reports.length > 0 ? (
        <ul className="mb-8 divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface">
          {reports.map((r) => (
            <li key={r.id} className="flex items-center justify-between gap-4 px-4 py-3">
              <Link href={`/reports/${r.id}`} className="min-w-0 text-sm font-medium text-foreground hover:underline">
                {r.title}
              </Link>
              <span className="shrink-0 rounded-full bg-background-subtle px-2.5 py-0.5 text-xs font-medium text-foreground-muted">
                {KIND_LABELS[r.kind] ?? r.kind}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mb-8 rounded-lg border border-dashed border-border bg-surface p-6 text-sm text-foreground-muted">
          No reports yet. Write your first one below.
        </div>
      )}

      <div className="rounded-lg border border-border bg-surface p-6">
        <h2 className="mb-4 text-sm font-semibold text-foreground">New report</h2>
        <CreateReportForm />
      </div>
    </div>
  );
}
