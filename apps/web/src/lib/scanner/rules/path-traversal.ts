import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Path Traversal", url: "https://owasp.org/www-community/attacks/Path_Traversal" }];

const USER_INPUT_HINT = /\b(req\.(query|params|body)|request\.(GET|POST|args|form)|params\[|\$_(GET|POST|REQUEST)\[)/;

function makeMatch(ruleId: string, title: string, content: string, line: number): RuleMatch {
  return {
    ruleId,
    category: "path_traversal",
    title,
    severity: "high",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation: `${title} appears to build a filesystem path directly from a request-controlled value.`,
    impact: "An attacker can supply a value like ../../etc/passwd to read (or, on a write path, overwrite) files outside the intended directory.",
    remediation: "Resolve the final path and verify it is still inside the intended base directory before using it (e.g. compare path.resolve(base, input) against path.resolve(base)), or reject any input containing '..' / path separators outright.",
    secureExample: "const resolved = path.resolve(baseDir, userFile); if (!resolved.startsWith(baseDir)) throw new Error('invalid path');",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const pathTraversalRule: ScanRule = {
  id: "path-traversal",
  category: "path_traversal",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { match, line } of findAllMatches(
      content,
      /\b(fs\.(readFile|readFileSync|createReadStream|writeFile|writeFileSync)|open|send_file|sendFile)\s*\([^)]*\)/g,
    )) {
      if (USER_INPUT_HINT.test(match[0])) {
        findings.push(makeMatch("path-traversal-file-read", "File operation built from request-controlled input", content, line));
      }
    }

    return findings;
  },
};
