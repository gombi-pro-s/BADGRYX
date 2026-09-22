import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: SQL Injection", url: "https://owasp.org/www-community/attacks/SQL_Injection" }];

const SQL_KEYWORDS = "(SELECT|INSERT\\s+INTO|UPDATE|DELETE\\s+FROM)";

const PATTERNS: RegExp[] = [
  // "...SELECT ...` + variable
  new RegExp(`["'\`][^"'\`]*\\b${SQL_KEYWORDS}\\b[^"'\`]*["'\`]\\s*\\+\\s*[A-Za-z_$][\\w.]*`, "gi"),
  // variable + "...SELECT ..."
  new RegExp(`[A-Za-z_$][\\w.]*\\s*\\+\\s*["'\`][^"'\`]*\\b${SQL_KEYWORDS}\\b`, "gi"),
  // template literal interpolation: `SELECT ... ${x}`
  new RegExp("`[^`]*\\b" + SQL_KEYWORDS + "\\b[^`]*\\$\\{[^}]+\\}[^`]*`", "gi"),
  // python f-string: f"SELECT ... {x}"
  new RegExp('f["\'][^"\']*\\b' + SQL_KEYWORDS + '\\b[^"\']*\\{[^}]+\\}[^"\']*["\']', "gi"),
  // "SELECT ... %s" % (x) or "SELECT ...".format(x)
  new RegExp('["\'][^"\']*\\b' + SQL_KEYWORDS + '\\b[^"\']*["\']\\s*(%|\\.format\\()', "gi"),
  // PHP-style concatenation: "SELECT ..." . $x
  new RegExp('["\'][^"\']*\\b' + SQL_KEYWORDS + '\\b[^"\']*["\']\\s*\\.\\s*\\$', "gi"),
];

export const sqlInjectionRule: ScanRule = {
  id: "sql-injection",
  category: "sql_injection",
  run(file) {
    const findings: RuleMatch[] = [];
    const seenLines = new Set<number>();

    for (const pattern of PATTERNS) {
      for (const { line } of findAllMatches(file.content, pattern)) {
        if (seenLines.has(line)) continue;
        seenLines.add(line);
        findings.push({
          ruleId: "sql-injection-string-building",
          category: "sql_injection",
          title: "SQL query built by concatenating or interpolating untrusted input",
          severity: "high",
          confidence: "medium",
          lineStart: line,
          lineEnd: line,
          evidence: getLineText(file.content, line),
          explanation: "A SQL query string appears to be assembled by concatenating or interpolating a variable directly, rather than using a parameterized query.",
          impact: "If the interpolated value can be influenced by a user, an attacker can alter the query's logic to read, modify, or delete data outside what the application intends -- or bypass authentication entirely.",
          remediation: "Use parameterized queries / prepared statements (e.g. `db.query('... WHERE id = $1', [id])`) so the database driver, not string formatting, handles the value.",
          secureExample: "db.query('SELECT * FROM users WHERE id = $1', [userId]);",
          referenceLinks: REFERENCES,
          verificationStatus: "needs_review",
        });
      }
    }

    return findings;
  },
};
