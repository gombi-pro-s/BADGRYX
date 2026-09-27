"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import type { ReportKind } from "@/types/database";

export interface FormState {
  error: string | null;
}

const REPORT_KINDS: ReportKind[] = ["pentest_report", "methodology"];

function firstIssue(result: { error?: { issues: { message: string }[] } }, fallback: string) {
  return result.error?.issues[0]?.message ?? fallback;
}

const reportSchema = z.object({
  title: z.string().trim().min(1).max(200),
  kind: z.enum(REPORT_KINDS as [ReportKind, ...ReportKind[]]),
  content_markdown: z.string().trim().min(1, "Report content is required."),
});

export async function createReportAction(_prev: FormState, formData: FormData): Promise<FormState> {
  const user = await requireUser();
  const parsed = reportSchema.safeParse({
    title: formData.get("title"),
    kind: formData.get("kind"),
    content_markdown: formData.get("content_markdown"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("reports")
    .insert({
      user_id: user.id,
      title: parsed.data.title,
      kind: parsed.data.kind,
      content_markdown: parsed.data.content_markdown,
    })
    .select("id")
    .single();
  if (error || !data) return { error: error?.message ?? "Failed to create report." };

  revalidatePath("/reports");
  redirect(`/reports/${data.id}`);
}

export async function updateReportAction(
  reportId: string,
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  await requireUser();
  const parsed = reportSchema.safeParse({
    title: formData.get("title"),
    kind: formData.get("kind"),
    content_markdown: formData.get("content_markdown"),
  });
  if (!parsed.success) return { error: firstIssue(parsed, "Invalid input.") };

  const supabase = await createClient();
  const { error } = await supabase
    .from("reports")
    .update({
      title: parsed.data.title,
      kind: parsed.data.kind,
      content_markdown: parsed.data.content_markdown,
    })
    .eq("id", reportId);
  if (error) return { error: error.message };

  revalidatePath("/reports");
  revalidatePath(`/reports/${reportId}`);
  return { error: null };
}

export async function deleteReportAction(reportId: string) {
  await requireUser();
  const supabase = await createClient();
  const { error } = await supabase.from("reports").delete().eq("id", reportId);
  if (error) throw new Error(error.message);
  revalidatePath("/reports");
  redirect("/reports");
}
