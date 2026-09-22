"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";

export interface SubmitFormState {
  error: string | null;
}

const submitSchema = z.object({
  report_content: z.string().trim().min(1, "A report is required.").max(20000),
});

export async function submitCapstoneReportAction(
  capstoneId: string,
  _prev: SubmitFormState,
  formData: FormData,
): Promise<SubmitFormState> {
  const user = await requireUser();
  const parsed = submitSchema.safeParse({ report_content: formData.get("report_content") });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? "Invalid input." };

  const supabase = await createClient();
  const { error } = await supabase.from("capstone_submissions").insert({
    capstone_id: capstoneId,
    user_id: user.id,
    report_content: parsed.data.report_content,
  });
  if (error) return { error: error.message };

  revalidatePath(`/capstones/${capstoneId}`);
  revalidatePath("/capstones");
  return { error: null };
}
