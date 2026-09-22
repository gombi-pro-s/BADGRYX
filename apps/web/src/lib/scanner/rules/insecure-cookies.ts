import type { RuleMatch, ScanRule } from "./types";
import { extractBalanced, findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Session Management Cheat Sheet", url: "https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html" }];

function makeMatch(ruleId: string, title: string, content: string, line: number, explanation: string): RuleMatch {
  return {
    ruleId,
    category: "insecure_cookies",
    title,
    severity: "medium",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation,
    impact: "A cookie missing HttpOnly can be read by any injected/third-party JavaScript (worsening the impact of an XSS bug); missing Secure means it can be sent over plain HTTP and intercepted; missing SameSite widens exposure to CSRF.",
    remediation: "Set httpOnly: true and secure: true (in production) and an explicit sameSite policy ('lax' or 'strict') on every cookie that holds a session or auth token.",
    secureExample: "res.cookie('session', token, { httpOnly: true, secure: true, sameSite: 'lax' });",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const insecureCookiesRule: ScanRule = {
  id: "insecure-cookies",
  category: "insecure_cookies",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { match, line } of findAllMatches(content, /\bres(?:ponse)?\.cookie\s*\(/g)) {
      const openIndex = match.index + match[0].length - 1;
      const args = extractBalanced(content, openIndex);
      const hasHttpOnly = /httpOnly\s*:\s*true/.test(args);
      const hasSecure = /secure\s*:\s*true/.test(args);
      if (!hasHttpOnly || !hasSecure) {
        const missing = [!hasHttpOnly && "HttpOnly", !hasSecure && "Secure"].filter(Boolean).join(" and ");
        findings.push(makeMatch("insecure-cookies-missing-flags", `Cookie set without ${missing}`, content, line,
          `res.cookie() is called without the ${missing} flag(s) set to true.`));
      }
    }

    for (const { line } of findAllMatches(content, /\bSet-Cookie["'`:]\s*[^;\n]*=/gi)) {
      const lineText = getLineText(content, line);
      if (!/HttpOnly/i.test(lineText) && !/\bres\.cookie\b/.test(lineText)) {
        findings.push(makeMatch("insecure-cookies-raw-header", "Set-Cookie header built without HttpOnly", content, line,
          "A Set-Cookie header is constructed directly without an HttpOnly attribute."));
      }
    }

    return findings;
  },
};
