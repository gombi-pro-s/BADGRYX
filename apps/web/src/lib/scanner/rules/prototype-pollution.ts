import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Prototype Pollution Prevention Cheat Sheet", url: "https://cheatsheetseries.owasp.org/cheatsheets/Prototype_Pollution_Prevention_Cheat_Sheet.html" }];

function makeMatch(ruleId: string, title: string, content: string, line: number, explanation: string): RuleMatch {
  return {
    ruleId,
    category: "prototype_pollution",
    title,
    severity: "high",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation,
    impact: "If an attacker can control the object being merged/assigned (e.g. request body JSON), they can set __proto__.polluted = true and affect every object in the process, potentially bypassing authorization checks or crashing the application.",
    remediation: "Validate/allow-list the keys of any object built from untrusted input before merging it, or use a merge utility with built-in prototype-pollution protection (e.g. a recent lodash with the CVE fix, or Object.create(null) for the target).",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

const UNTRUSTED_SOURCE = /\b(req\.body|request\.body|JSON\.parse\()/;

export const prototypePollutionRule: ScanRule = {
  id: "prototype-pollution",
  category: "prototype_pollution",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { match, line } of findAllMatches(content, /\b(_\.merge|_\.defaultsDeep|Object\.assign)\s*\([^)]*\)/g)) {
      if (UNTRUSTED_SOURCE.test(match[0])) {
        findings.push(makeMatch("prototype-pollution-deep-merge", "Object merged with untrusted input via a deep-merge utility", content, line,
          "A deep-merge call (lodash merge/defaultsDeep or Object.assign) includes a value sourced from request input."));
      }
    }

    for (const { line } of findAllMatches(content, /\[\s*(req\.(query|body|params)[.[][^\]]*|userKey|key)\s*\]\s*=/g)) {
      findings.push(makeMatch("prototype-pollution-computed-key-assignment", "Object property assigned via a computed key derived from request input", content, line,
        "A bracket-notation property assignment uses a key that comes from user input, which could be '__proto__' or 'constructor.prototype'."));
    }

    return findings;
  },
};
