import type { RuleMatch, ScanRule } from "./types";
import { extractBalanced, findAllMatches, getLineText, isStaticStringLiteral } from "./util";

const REFERENCES = [{ title: "OWASP: Command Injection", url: "https://owasp.org/www-community/attacks/Command_Injection" }];

function makeMatch(ruleId: string, title: string, content: string, line: number, evidenceOverride?: string): RuleMatch {
  return {
    ruleId,
    category: "command_injection",
    title,
    severity: "critical",
    confidence: "medium",
    lineStart: line,
    lineEnd: line,
    evidence: evidenceOverride ?? getLineText(content, line),
    explanation: `${title}, with a command string that is not a fixed literal.`,
    impact: "If the dynamic portion of the command can be influenced by user input, an attacker can inject shell metacharacters (;, |, &&, backticks) to run arbitrary commands with the application's privileges.",
    remediation: "Avoid a shell entirely: call the target program directly with an argument array (e.g. execFile/spawn without shell:true, subprocess.run([...], shell=False)) so arguments are never re-parsed by a shell.",
    secureExample: "child_process.execFile('convert', [inputPath, outputPath]);",
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const commandInjectionRule: ScanRule = {
  id: "command-injection",
  category: "command_injection",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { match, line } of findAllMatches(content, /\b(exec|execSync)\s*\(/g)) {
      const openIndex = match.index + match[0].length - 1;
      const args = extractBalanced(content, openIndex);
      const firstArg = args.split(",")[0] ?? args;
      if (!isStaticStringLiteral(firstArg)) {
        findings.push(makeMatch("command-injection-node-exec", "child_process.exec() called with a dynamic command string", content, line));
      }
    }

    for (const { line } of findAllMatches(content, /\bspawn\s*\([^)]*shell\s*:\s*true/g)) {
      findings.push(makeMatch("command-injection-node-spawn-shell", "child_process.spawn() invoked with shell: true", content, line));
    }

    for (const { line } of findAllMatches(content, /\bos\.system\s*\(/g)) {
      findings.push(makeMatch("command-injection-python-os-system", "os.system() called (always runs through a shell)", content, line));
    }

    for (const { line } of findAllMatches(content, /\bsubprocess\.(run|call|Popen)\s*\([^)]*shell\s*=\s*True/g)) {
      findings.push(makeMatch("command-injection-python-subprocess-shell", "subprocess called with shell=True", content, line));
    }

    for (const { line } of findAllMatches(content, /\b(shell_exec|passthru|system|popen)\s*\(\s*\$/g)) {
      findings.push(makeMatch("command-injection-php-shell", "PHP shell function called with a variable argument", content, line));
    }

    return findings;
  },
};
