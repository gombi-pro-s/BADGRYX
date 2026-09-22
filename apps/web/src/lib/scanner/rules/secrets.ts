import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Use of Hard-coded Credentials", url: "https://owasp.org/www-community/vulnerabilities/Use_of_hard-coded_password" }];

const PLACEHOLDER_PATTERN = /^(changeme|change_me|your[_-]|example|xxx|todo|<|\{\{|\$\{|process\.env|os\.environ|env\[|getenv)/i;

function isPlaceholder(value: string): boolean {
  const stripped = value.replace(/^["'`]|["'`]$/g, "");
  if (stripped.length < 8) return true;
  return PLACEHOLDER_PATTERN.test(stripped);
}

function makeMatch(
  ruleId: string,
  title: string,
  content: string,
  lineNumber: number,
  confidence: "high" | "medium",
): RuleMatch {
  return {
    ruleId,
    category: "secrets",
    title,
    severity: "critical",
    confidence,
    lineStart: lineNumber,
    lineEnd: lineNumber,
    evidence: getLineText(content, lineNumber),
    explanation: `${title} was found hardcoded directly in source.`,
    impact: "Anyone with read access to this source (including version control history) can use this credential to impersonate the application or access the service it authenticates to.",
    remediation: "Remove the credential from source, rotate it immediately (assume it is compromised), and load it at runtime from an environment variable or secrets manager instead.",
    referenceLinks: REFERENCES,
    verificationStatus: confidence === "high" ? "true_positive" : "needs_review",
  };
}

const STRUCTURED_TOKEN_PATTERNS: { id: string; title: string; pattern: RegExp }[] = [
  { id: "secrets-aws-access-key", title: "AWS Access Key ID", pattern: /\bAKIA[0-9A-Z]{16}\b/g },
  { id: "secrets-github-token", title: "GitHub personal access token", pattern: /\bgh[pousr]_[A-Za-z0-9]{36,}\b/g },
  { id: "secrets-slack-token", title: "Slack token", pattern: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/g },
  { id: "secrets-stripe-key", title: "Stripe secret key", pattern: /\bsk_(live|test)_[A-Za-z0-9]{16,}\b/g },
  { id: "secrets-private-key-block", title: "Private key material", pattern: /-----BEGIN (RSA |EC |DSA |OPENSSH |)PRIVATE KEY-----/g },
];

const GENERIC_ASSIGNMENT_PATTERN =
  /\b(api[_-]?key|secret[_-]?key|secret|password|passwd|access[_-]?key|private[_-]?key|auth[_-]?token|client[_-]?secret)\b\s*[:=]\s*["'`]([^"'`]{6,})["'`]/gi;

export const secretsRule: ScanRule = {
  id: "secrets",
  category: "secrets",
  run(file) {
    const findings: RuleMatch[] = [];
    const seenLines = new Set<number>();

    for (const { id, title, pattern } of STRUCTURED_TOKEN_PATTERNS) {
      for (const { line } of findAllMatches(file.content, pattern)) {
        if (seenLines.has(line)) continue;
        seenLines.add(line);
        findings.push(makeMatch(id, title, file.content, line, "high"));
      }
    }

    for (const { match, line } of findAllMatches(file.content, GENERIC_ASSIGNMENT_PATTERN)) {
      if (seenLines.has(line)) continue;
      const value = match[2] ?? "";
      if (isPlaceholder(value)) continue;
      seenLines.add(line);
      findings.push(makeMatch("secrets-generic-assignment", `Hardcoded ${match[1]}`, file.content, line, "medium"));
    }

    return findings;
  },
};
