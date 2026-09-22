import type { RuleMatch, ScanRule } from "./types";
import { extractBalanced, findAllMatches, getLineText, isStaticStringLiteral } from "./util";

const REFERENCES = [{ title: "OWASP: Code Injection", url: "https://owasp.org/www-community/attacks/Code_Injection" }];

function makeMatch(ruleId: string, title: string, content: string, line: number): RuleMatch {
  return {
    ruleId,
    category: "insecure_eval",
    title,
    severity: "critical",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation: `${title}, with a non-literal argument.`,
    impact: "If the evaluated string can be influenced by user input, an attacker can run arbitrary code with the application's privileges -- this is typically a full remote code execution vulnerability, not just an injection.",
    remediation: "Avoid evaluating dynamic strings as code entirely. If dynamic behavior is genuinely needed, use a safe, restricted alternative (a lookup table of allowed functions, a sandboxed expression evaluator) instead of eval/Function/exec.",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const insecureEvalRule: ScanRule = {
  id: "insecure-eval",
  category: "insecure_eval",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { match, line } of findAllMatches(content, /\beval\s*\(/g)) {
      const openIndex = match.index + match[0].length - 1;
      const args = extractBalanced(content, openIndex);
      if (!isStaticStringLiteral(args)) {
        findings.push(makeMatch("insecure-eval-eval", "eval() called with a dynamic argument", content, line));
      }
    }

    for (const { line } of findAllMatches(content, /\bnew\s+Function\s*\(/g)) {
      findings.push(makeMatch("insecure-eval-new-function", "new Function() used to build code from a string at runtime", content, line));
    }

    for (const { match, line } of findAllMatches(content, /\b(setTimeout|setInterval)\s*\(\s*["'`]/g)) {
      findings.push(makeMatch("insecure-eval-settimeout-string", `${match[1]}() called with a string argument (implicit eval)`, content, line));
    }

    for (const { match, line } of findAllMatches(content, /\bexec\s*\(/g)) {
      const openIndex = match.index + match[0].length - 1;
      const args = extractBalanced(content, openIndex);
      if (!isStaticStringLiteral(args) && file.language === "python") {
        findings.push(makeMatch("insecure-eval-python-exec", "Python exec() called with a dynamic argument", content, line));
      }
    }

    return findings;
  },
};
