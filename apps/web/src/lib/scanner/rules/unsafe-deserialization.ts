import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Deserialization Cheat Sheet", url: "https://cheatsheetseries.owasp.org/cheatsheets/Deserialization_Cheat_Sheet.html" }];

function makeMatch(ruleId: string, title: string, content: string, line: number, explanation: string, remediation: string): RuleMatch {
  return {
    ruleId,
    category: "unsafe_deserialization",
    title,
    severity: "critical",
    confidence: "high",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation,
    impact: "Deserializing untrusted data with a format that can reconstruct arbitrary objects (rather than plain data) typically allows an attacker to achieve remote code execution by crafting a malicious payload.",
    remediation,
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const unsafeDeserializationRule: ScanRule = {
  id: "unsafe-deserialization",
  category: "unsafe_deserialization",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { line } of findAllMatches(content, /\bpickle\.loads?\s*\(/g)) {
      findings.push(makeMatch("unsafe-deserialization-python-pickle", "Python pickle used to deserialize data", content, line,
        "pickle.load/loads can execute arbitrary code during deserialization if the input is attacker-controlled.",
        "Use a data-only format (JSON) unless the source is fully trusted; if pickle is unavoidable, never deserialize data that crossed a trust boundary."));
    }

    for (const { match, line } of findAllMatches(content, /\byaml\.load\s*\(([^)]*)\)/g)) {
      if (!/Loader\s*=\s*yaml\.(SafeLoader|CSafeLoader)/.test(match[1] ?? "")) {
        findings.push(makeMatch("unsafe-deserialization-python-yaml", "yaml.load() called without SafeLoader", content, line,
          "PyYAML's default Loader can construct arbitrary Python objects from the YAML document, including ones that execute code on construction.",
          "Use yaml.safe_load() (or yaml.load(data, Loader=yaml.SafeLoader)) instead."));
      }
    }

    for (const { line } of findAllMatches(content, /\bunserialize\s*\(/g)) {
      findings.push(makeMatch("unsafe-deserialization-php-unserialize", "PHP unserialize() called", content, line,
        "PHP's unserialize() can instantiate arbitrary classes from the input, which is a well-known PHP object injection / RCE vector when the input is attacker-controlled.",
        "Use json_decode() for data interchange instead of PHP's native serialization format."));
    }

    for (const { line } of findAllMatches(content, /\bObjectInputStream\b|\breadObject\s*\(/g)) {
      findings.push(makeMatch("unsafe-deserialization-java-objectinputstream", "Java native deserialization (ObjectInputStream/readObject)", content, line,
        "Java native deserialization of untrusted data is a well-known RCE vector via gadget chains in classes already on the classpath.",
        "Use a data-only format (JSON/Protobuf) instead, or validate the class allow-list with a look-ahead deserialization filter if native deserialization is unavoidable."));
    }

    for (const { line } of findAllMatches(content, /\brequire\s*\(\s*["'`]node-serialize["'`]\s*\)|\bserialize\.unserialize\s*\(/g)) {
      findings.push(makeMatch("unsafe-deserialization-node-serialize", "node-serialize used to deserialize data", content, line,
        "The node-serialize package can execute embedded JavaScript during deserialization of attacker-controlled input.",
        "Use JSON.parse() for data interchange instead."));
    }

    return findings;
  },
};
