import type { RuleMatch, ScanRule } from "./types";
import { extractBalanced, findAllMatches, getLineText, isStaticStringLiteral } from "./util";

const REFERENCES = [{ title: "OWASP: Cross Site Scripting (XSS)", url: "https://owasp.org/www-community/attacks/xss/" }];

function xssMatch(ruleId: string, title: string, content: string, line: number): RuleMatch {
  return {
    ruleId,
    category: "xss",
    title,
    severity: "high",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation: `${title}, with content that is not a fixed string literal.`,
    impact: "If the rendered content can be influenced by user input, an attacker can inject a <script> tag or event handler that runs in another user's browser session -- stealing session tokens, defacing the page, or performing actions as that user.",
    remediation: "Set textContent instead of innerHTML for plain text, or run the value through a sanitizer (e.g. DOMPurify) before rendering it as HTML. Framework-managed text interpolation (e.g. {value} in JSX) is safe by default -- only bypasses like dangerouslySetInnerHTML need this.",
    secureExample: "element.textContent = userProvidedValue; // or DOMPurify.sanitize(html) before innerHTML",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const xssRule: ScanRule = {
  id: "xss",
  category: "xss",
  run(file) {
    const findings: RuleMatch[] = [];
    const { content } = file;

    for (const { match, line } of findAllMatches(content, /\.innerHTML\s*=/g)) {
      const eqIndex = match.index + match[0].length - 1;
      let end = eqIndex + 1;
      while (end < content.length && content[end] !== ";" && content[end] !== "\n") end++;
      const rhs = content.slice(eqIndex + 1, end);
      if (!isStaticStringLiteral(rhs)) {
        findings.push(xssMatch("xss-innerhtml-assignment", "innerHTML assigned dynamic content", content, line));
      }
    }

    for (const { match, line } of findAllMatches(content, /document\.write\s*\(/g)) {
      const openIndex = match.index + match[0].length - 1;
      const args = extractBalanced(content, openIndex);
      if (!isStaticStringLiteral(args)) {
        findings.push(xssMatch("xss-document-write", "document.write() called with dynamic content", content, line));
      }
    }

    for (const { match, line } of findAllMatches(content, /dangerouslySetInnerHTML\s*=\s*\{\{\s*__html\s*:/g)) {
      const braceIndex = content.indexOf("{{", match.index) + 1;
      const inner = extractBalanced(content, braceIndex, "{", "}");
      const htmlValue = inner.replace(/^\s*__html\s*:/, "");
      if (!isStaticStringLiteral(htmlValue)) {
        findings.push(xssMatch("xss-dangerously-set-innerhtml", "dangerouslySetInnerHTML used with dynamic content", content, line));
      }
    }

    for (const { match, line } of findAllMatches(content, /\bv-html\s*=\s*"([^"]+)"/g)) {
      const boundExpr = match[1] ?? "";
      if (!isStaticStringLiteral(`"${boundExpr}"`)) {
        findings.push(xssMatch("xss-vue-v-html", "Vue v-html bound to dynamic content", content, line));
      }
    }

    return findings.filter((f, idx, all) => all.findIndex((o) => o.lineStart === f.lineStart && o.ruleId === f.ruleId) === idx);
  },
};
