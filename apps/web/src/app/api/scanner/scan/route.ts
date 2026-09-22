import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { runScan, ScanValidationError } from "@/lib/scanner/orchestrate";
import { checkScannerQuota } from "@/lib/scanner/rate-limit";
import type { ScanTargetType } from "@/types/database";

const TARGET_TYPES: ScanTargetType[] = ["pasted_snippet", "uploaded_files"];

const fileSchema = z.object({
  filename: z.string().trim().min(1).max(255),
  content: z.string().min(1).max(300_000),
});

const requestSchema = z.object({
  title: z.string().trim().min(1).max(200).optional(),
  targetType: z.enum(TARGET_TYPES as [ScanTargetType, ...ScanTargetType[]]),
  files: z.array(fileSchema).min(1).max(20),
});

export async function POST(request: Request) {
  const user = await requireUser();

  const body = await request.json().catch(() => null);
  const parsed = requestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid request." }, { status: 400 });
  }
  const { title, targetType, files } = parsed.data;

  const supabase = await createClient();

  const quota = await checkScannerQuota(supabase, user.id);
  if (!quota.allowed) {
    return NextResponse.json(
      { error: `Daily scan limit reached (${quota.used}/${quota.limit}). Try again tomorrow, or upgrade your plan.` },
      { status: 429 },
    );
  }

  const scanTitle = title || (files.length === 1 ? files[0].filename : `Scan of ${files.length} files`);

  try {
    const result = await runScan(supabase, user.id, scanTitle, targetType, files);

    await supabase.rpc("log_audit_event", {
      p_action: "scan.completed",
      p_target_type: "scan",
      p_target_id: result.scanId,
      p_metadata: { total_files: result.totalFiles, total_findings: result.totalFindings },
    });

    return NextResponse.json({
      ...result,
      quota: { used: quota.used + 1, limit: quota.limit },
    });
  } catch (err) {
    if (err instanceof ScanValidationError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error("Scan failed:", err);
    return NextResponse.json({ error: "The scan could not be completed. Please try again." }, { status: 502 });
  }
}
