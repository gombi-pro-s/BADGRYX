import "server-only";

import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import { getAnthropicApiKey } from "@/lib/env";
import type { Database, ScanFindingRow } from "@/types/database";
import { buildEnrichmentSystemPrompt, ENRICHMENT_USER_TURN, type EnrichmentFinding } from "./enrichment-prompt";

const MODEL = "claude-sonnet-5";
const MAX_TOKENS = 1024;

const enrichmentOutputSchema = z.object({
  explanation: z.string().trim().min(1),
  impact: z.string().trim().min(1),
  remediation: z.string().trim().min(1),
  secureExample: z.string().trim().min(1).nullable(),
});

export class EnrichmentError extends Error {}
export class FindingNotFoundError extends Error {}

/**
 * Fetches a finding the caller owns (RLS-enforced -- this uses the caller's
 * own session, not service_role), asks Anthropic to improve its
 * explanation/impact/remediation grounded in the finding's real evidence,
 * and writes the result via enrich_scan_finding() -- the only function that
 * can touch those fields, and one with no parameter that could change
 * severity/category/verification_status/status (see
 * supabase/migrations/20260922000004_scanner_enrichment.sql). A prompt
 * injection embedded in the scanned source code (the one thing in this flow
 * that is attacker-influenceable) could at worst produce bad *text*; it has
 * no path to a bad *write*.
 */
export async function enrichScanFinding(
  supabase: SupabaseClient<Database>,
  findingId: string,
): Promise<ScanFindingRow> {
  const { data: finding, error: findingError } = await supabase
    .from("scan_findings")
    .select("rule_id, category, title, severity, confidence, line_start, line_end, evidence, explanation, impact, remediation, file_id")
    .eq("id", findingId)
    .maybeSingle();
  if (findingError) throw new Error(`Failed to load finding: ${findingError.message}`);
  if (!finding) throw new FindingNotFoundError("Finding not found.");

  const { data: file, error: fileError } = await supabase
    .from("scan_files")
    .select("filename")
    .eq("id", finding.file_id)
    .maybeSingle();
  if (fileError) throw new Error(`Failed to load finding's file: ${fileError.message}`);

  const promptInput: EnrichmentFinding = {
    ruleId: finding.rule_id,
    category: finding.category,
    title: finding.title,
    severity: finding.severity,
    confidence: finding.confidence,
    filename: file?.filename ?? "unknown file",
    lineStart: finding.line_start,
    lineEnd: finding.line_end,
    evidence: finding.evidence,
    currentExplanation: finding.explanation,
    currentImpact: finding.impact,
    currentRemediation: finding.remediation,
  };

  const client = new Anthropic({ apiKey: getAnthropicApiKey() });
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system: buildEnrichmentSystemPrompt(promptInput),
    messages: [{ role: "user", content: ENRICHMENT_USER_TURN }],
  });

  const textBlock = response.content.find((block) => block.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new EnrichmentError("Enrichment response contained no text content.");
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(textBlock.text);
  } catch {
    throw new EnrichmentError("Enrichment response was not valid JSON.");
  }

  const parsed = enrichmentOutputSchema.safeParse(parsedJson);
  if (!parsed.success) {
    throw new EnrichmentError(`Enrichment response did not match the expected shape: ${parsed.error.issues[0]?.message}`);
  }

  const { data: updated, error: rpcError } = await supabase.rpc("enrich_scan_finding", {
    p_finding_id: findingId,
    p_explanation: parsed.data.explanation,
    p_impact: parsed.data.impact,
    p_remediation: parsed.data.remediation,
    p_secure_example: parsed.data.secureExample,
  });
  if (rpcError || !updated) {
    throw new Error(`Failed to save enrichment: ${rpcError?.message ?? "unknown error"}`);
  }

  return updated;
}
