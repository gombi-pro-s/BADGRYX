import type { RuleMatch, ScanInputFile, ScanRule } from "./types";
import { secretsRule } from "./secrets";
import { sqlInjectionRule } from "./sql-injection";
import { xssRule } from "./xss";
import { commandInjectionRule } from "./command-injection";
import { pathTraversalRule } from "./path-traversal";
import { insecureEvalRule } from "./insecure-eval";
import { weakCryptoRule } from "./weak-crypto";
import { insecureCorsRule } from "./insecure-cors";
import { insecureCookiesRule } from "./insecure-cookies";
import { cleartextHttpRule } from "./cleartext-http";
import { prototypePollutionRule } from "./prototype-pollution";
import { unsafeDeserializationRule } from "./unsafe-deserialization";

export type { RuleMatch, ScanInputFile, ScanRule } from "./types";

/**
 * Every rule the deterministic static-analysis engine runs. This is the
 * "don't rely exclusively on an LLM" core the spec calls for (section 8):
 * plain pattern matching over source text, with no model call and no
 * network access, so results are reproducible and explainable by pointing
 * at the exact regex/heuristic that fired.
 *
 * This is intentionally not a claim of completeness -- these are
 * string/regex heuristics, not a real parser or dataflow analysis, so they
 * will miss real vulnerabilities (false negatives) and occasionally flag
 * safe code (false positives, mitigated by `verificationStatus` and the
 * attack -> fix -> retest workflow letting a human mark a finding
 * false_positive). See docs/adr/0008-scanner-finding-lifecycle.md.
 */
export const ALL_RULES: ScanRule[] = [
  secretsRule,
  sqlInjectionRule,
  xssRule,
  commandInjectionRule,
  pathTraversalRule,
  insecureEvalRule,
  weakCryptoRule,
  insecureCorsRule,
  insecureCookiesRule,
  cleartextHttpRule,
  prototypePollutionRule,
  unsafeDeserializationRule,
];

/** Runs every applicable rule against one file and returns all matches, in a stable order (by rule, then by line). */
export function runRulesOnFile(file: ScanInputFile, rules: ScanRule[] = ALL_RULES): RuleMatch[] {
  const findings: RuleMatch[] = [];
  for (const rule of rules) {
    if (rule.languages && (!file.language || !rule.languages.includes(file.language))) continue;
    findings.push(...rule.run(file));
  }
  return findings.sort((a, b) => a.lineStart - b.lineStart || a.ruleId.localeCompare(b.ruleId));
}
