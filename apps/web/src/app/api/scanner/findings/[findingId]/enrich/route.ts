import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { enrichScanFinding, EnrichmentError, FindingNotFoundError } from "@/lib/scanner/enrich";
import { checkEnrichmentQuota } from "@/lib/scanner/rate-limit";

const paramsSchema = z.object({ findingId: z.uuid() });

export async function POST(_request: Request, { params }: { params: Promise<{ findingId: string }> }) {
  const user = await requireUser();

  const parsedParams = paramsSchema.safeParse(await params);
  if (!parsedParams.success) {
    return NextResponse.json({ error: "Invalid finding id." }, { status: 400 });
  }

  const supabase = await createClient();

  const quota = await checkEnrichmentQuota(supabase, user.id);
  if (!quota.allowed) {
    return NextResponse.json(
      { error: `Daily AI enrichment limit reached (${quota.used}/${quota.limit}). Try again tomorrow, or upgrade your plan.` },
      { status: 429 },
    );
  }

  try {
    const finding = await enrichScanFinding(supabase, parsedParams.data.findingId);
    return NextResponse.json({ finding, quota: { used: quota.used + 1, limit: quota.limit } });
  } catch (err) {
    if (err instanceof FindingNotFoundError) {
      return NextResponse.json({ error: err.message }, { status: 404 });
    }
    if (err instanceof EnrichmentError) {
      console.error("Scan finding enrichment returned an unusable response:", err);
      return NextResponse.json({ error: "Enrichment is temporarily unavailable. Please try again shortly." }, { status: 502 });
    }
    console.error("Scan finding enrichment failed:", err);
    return NextResponse.json({ error: "Enrichment is temporarily unavailable. Please try again shortly." }, { status: 502 });
  }
}
