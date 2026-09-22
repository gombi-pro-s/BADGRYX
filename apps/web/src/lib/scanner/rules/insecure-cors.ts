import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: CORS misconfiguration", url: "https://owasp.org/www-community/attacks/CORS_OriginHeaderScrutiny" }];

function makeMatch(ruleId: string, title: string, content: string, line: number, explanation: string): RuleMatch {
  return {
    ruleId,
    category: "insecure_cors",
    title,
    severity: "high",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation,
    impact: "A wildcard or reflected CORS origin lets any website make authenticated, credentialed requests to this API on behalf of a logged-in user, reading responses the browser's same-origin policy would otherwise block.",
    remediation: "Allow-list specific known origins instead of '*' or reflecting the request's Origin header verbatim; never combine a wildcard origin with Access-Control-Allow-Credentials: true.",
    secureExample: "cors({ origin: ['https://app.example.com'], credentials: true });",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const insecureCorsRule: ScanRule = {
  id: "insecure-cors",
  category: "insecure_cors",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { line } of findAllMatches(content, /Access-Control-Allow-Origin["'`]?\s*[,:]\s*["'`]\*["'`]/gi)) {
      findings.push(makeMatch("insecure-cors-wildcard-header", "Access-Control-Allow-Origin set to '*'", content, line,
        "The CORS response header explicitly allows every origin."));
    }

    for (const { line } of findAllMatches(content, /\borigin\s*:\s*(true|["'`]\*["'`])/g)) {
      findings.push(makeMatch("insecure-cors-wildcard-config", "CORS middleware configured to allow any origin", content, line,
        "The CORS configuration allows every origin (origin: true or origin: '*')."));
    }

    for (const { line } of findAllMatches(content, /Access-Control-Allow-Origin["'`]?\s*,\s*(req|request)\.(headers\.)?origin/gi)) {
      findings.push(makeMatch("insecure-cors-reflected-origin", "Access-Control-Allow-Origin reflects the request's Origin header without validation", content, line,
        "The response echoes back whatever Origin the requester sent, which is equivalent to a wildcard for any site that sends credentials."));
    }

    return findings;
  },
};
