import { describe, expect, it } from "vitest";
import { secretsRule } from "../secrets";
import { sqlInjectionRule } from "../sql-injection";
import { xssRule } from "../xss";
import { commandInjectionRule } from "../command-injection";
import { pathTraversalRule } from "../path-traversal";
import { insecureEvalRule } from "../insecure-eval";
import { weakCryptoRule } from "../weak-crypto";
import { insecureCorsRule } from "../insecure-cors";
import { insecureCookiesRule } from "../insecure-cookies";
import { cleartextHttpRule } from "../cleartext-http";
import { prototypePollutionRule } from "../prototype-pollution";
import { unsafeDeserializationRule } from "../unsafe-deserialization";
import type { ScanInputFile, ScanRule } from "../types";

function file(content: string, filename = "app.js", language: string | null = "javascript"): ScanInputFile {
  return { filename, language, content };
}

function expectRuleId(rule: ScanRule, content: string, ruleId: string, filename?: string, language?: string | null) {
  const findings = rule.run(file(content, filename, language ?? undefined));
  expect(findings.some((f) => f.ruleId === ruleId), `expected a ${ruleId} finding in:\n${content}`).toBe(true);
}

function expectNoFindings(rule: ScanRule, content: string, filename?: string, language?: string | null) {
  const findings = rule.run(file(content, filename, language ?? undefined));
  expect(findings, `expected no findings in:\n${content}\ngot: ${JSON.stringify(findings)}`).toHaveLength(0);
}

describe("secretsRule", () => {
  it("flags an AWS access key", () => {
    expectRuleId(secretsRule, `const key = "AKIAIOSFODNN7EXAMPLE";`, "secrets-aws-access-key");
  });
  it("flags a GitHub token", () => {
    expectRuleId(secretsRule, `const token = "ghp_${"a".repeat(36)}";`, "secrets-github-token");
  });
  it("flags a PEM private key block", () => {
    expectRuleId(secretsRule, "-----BEGIN RSA PRIVATE KEY-----\nMIIBOgIBAAJBAK...\n-----END RSA PRIVATE KEY-----", "secrets-private-key-block");
  });
  it("flags a hardcoded generic password assignment", () => {
    expectRuleId(secretsRule, `const password = "SuperSecret123!";`, "secrets-generic-assignment");
  });
  it("does not flag a password read from an environment variable", () => {
    expectNoFindings(secretsRule, `const password = process.env.DB_PASSWORD;`);
  });
  it("does not flag an obvious placeholder value", () => {
    expectNoFindings(secretsRule, `const apiKey = "your_api_key_here";`);
  });
});

describe("sqlInjectionRule", () => {
  it("flags string concatenation building a SQL query", () => {
    expectRuleId(sqlInjectionRule, `const query = "SELECT * FROM users WHERE id = " + req.query.id;`, "sql-injection-string-building");
  });
  it("flags a template literal interpolating into a SQL query", () => {
    expectRuleId(sqlInjectionRule, "const query = `SELECT * FROM users WHERE id = ${userId}`;", "sql-injection-string-building");
  });
  it("flags a Python f-string SQL query", () => {
    expectRuleId(sqlInjectionRule, `query = f"SELECT * FROM users WHERE id = {user_id}"`, "sql-injection-string-building", "app.py", "python");
  });
  it("does not flag a parameterized query", () => {
    expectNoFindings(sqlInjectionRule, `db.query("SELECT * FROM users WHERE id = $1", [userId]);`);
  });
});

describe("xssRule", () => {
  it("flags innerHTML assigned a variable", () => {
    expectRuleId(xssRule, `el.innerHTML = userComment;`, "xss-innerhtml-assignment");
  });
  it("flags innerHTML built by concatenation", () => {
    expectRuleId(xssRule, `el.innerHTML = "<b>" + name + "</b>";`, "xss-innerhtml-assignment");
  });
  it("does not flag innerHTML assigned a static string literal", () => {
    expectNoFindings(xssRule, `el.innerHTML = "<b>Hello</b>";`);
  });
  it("flags document.write with a dynamic argument", () => {
    expectRuleId(xssRule, `document.write(userInput);`, "xss-document-write");
  });
  it("does not flag document.write with a static string", () => {
    expectNoFindings(xssRule, `document.write("<hr>");`);
  });
});

describe("commandInjectionRule", () => {
  it("flags exec() with a dynamic command", () => {
    expectRuleId(commandInjectionRule, `exec("ls " + userDir);`, "command-injection-node-exec");
  });
  it("does not flag exec() with a static command", () => {
    expectNoFindings(commandInjectionRule, `exec("ls -la /tmp");`);
  });
  it("flags spawn with shell: true", () => {
    expectRuleId(commandInjectionRule, `spawn(cmd, args, { shell: true });`, "command-injection-node-spawn-shell");
  });
  it("flags Python subprocess with shell=True", () => {
    expectRuleId(commandInjectionRule, `subprocess.run(cmd, shell=True)`, "command-injection-python-subprocess-shell", "app.py", "python");
  });
  it("does not flag subprocess without shell=True", () => {
    expectNoFindings(commandInjectionRule, `subprocess.run(["ls", "-la"])`, "app.py", "python");
  });
});

describe("pathTraversalRule", () => {
  it("flags a file read built from request input", () => {
    expectRuleId(pathTraversalRule, `fs.readFile(path.join(baseDir, req.query.file), cb);`, "path-traversal-file-read");
  });
  it("does not flag a file read from a fixed path", () => {
    expectNoFindings(pathTraversalRule, `fs.readFile("/etc/app/config.json", cb);`);
  });
});

describe("insecureEvalRule", () => {
  it("flags eval() with a dynamic argument", () => {
    expectRuleId(insecureEvalRule, `eval(userExpression);`, "insecure-eval-eval");
  });
  it("does not flag eval() with a static string", () => {
    expectNoFindings(insecureEvalRule, `eval("1 + 1");`);
  });
  it("flags new Function()", () => {
    expectRuleId(insecureEvalRule, `const fn = new Function("a", "b", body);`, "insecure-eval-new-function");
  });
  it("flags setTimeout called with a string", () => {
    expectRuleId(insecureEvalRule, `setTimeout("doThing()", 1000);`, "insecure-eval-settimeout-string");
  });
});

describe("weakCryptoRule", () => {
  it("flags MD5 hashing", () => {
    expectRuleId(weakCryptoRule, `const hash = crypto.createHash("md5").update(data).digest("hex");`, "weak-crypto-md5");
  });
  it("does not flag SHA-256 hashing", () => {
    expectNoFindings(weakCryptoRule, `const hash = crypto.createHash("sha256").update(data).digest("hex");`);
  });
  it("flags Math.random() used for a token", () => {
    expectRuleId(weakCryptoRule, `const sessionToken = Math.random().toString(36);`, "weak-crypto-insecure-random");
  });
  it("does not flag Math.random() used for a non-security purpose", () => {
    expectNoFindings(weakCryptoRule, `const shuffleIndex = Math.random();`);
  });
});

describe("insecureCorsRule", () => {
  it("flags a wildcard Access-Control-Allow-Origin header", () => {
    expectRuleId(insecureCorsRule, `res.setHeader("Access-Control-Allow-Origin", "*");`, "insecure-cors-wildcard-header");
  });
  it("flags cors({ origin: true })", () => {
    expectRuleId(insecureCorsRule, `app.use(cors({ origin: true }));`, "insecure-cors-wildcard-config");
  });
  it("does not flag an explicit origin allow-list", () => {
    expectNoFindings(insecureCorsRule, `app.use(cors({ origin: ["https://app.example.com"] }));`);
  });
});

describe("insecureCookiesRule", () => {
  it("flags res.cookie() without httpOnly/secure", () => {
    expectRuleId(insecureCookiesRule, `res.cookie("session", token);`, "insecure-cookies-missing-flags");
  });
  it("does not flag res.cookie() with httpOnly and secure set", () => {
    expectNoFindings(insecureCookiesRule, `res.cookie("session", token, { httpOnly: true, secure: true, sameSite: "lax" });`);
  });
});

describe("cleartextHttpRule", () => {
  it("flags a hardcoded http:// URL", () => {
    expectRuleId(cleartextHttpRule, `const apiUrl = "http://api.example-service.com/v1";`, "cleartext-http-hardcoded-url");
  });
  it("does not flag a localhost URL", () => {
    expectNoFindings(cleartextHttpRule, `const devUrl = "http://localhost:3000";`);
  });
  it("does not flag an https URL", () => {
    expectNoFindings(cleartextHttpRule, `const apiUrl = "https://api.example-service.com/v1";`);
  });
});

describe("prototypePollutionRule", () => {
  it("flags a deep merge of request body input", () => {
    expectRuleId(prototypePollutionRule, `const merged = _.merge({}, req.body);`, "prototype-pollution-deep-merge");
  });
  it("does not flag a deep merge of a fixed config object", () => {
    expectNoFindings(prototypePollutionRule, `const merged = _.merge({}, defaultConfig, overrideConfig);`);
  });
});

describe("unsafeDeserializationRule", () => {
  it("flags pickle.loads", () => {
    expectRuleId(unsafeDeserializationRule, `data = pickle.loads(payload)`, "unsafe-deserialization-python-pickle", "app.py", "python");
  });
  it("flags yaml.load without SafeLoader", () => {
    expectRuleId(unsafeDeserializationRule, `config = yaml.load(raw)`, "unsafe-deserialization-python-yaml", "app.py", "python");
  });
  it("does not flag yaml.safe_load-equivalent usage", () => {
    expectNoFindings(unsafeDeserializationRule, `config = yaml.load(raw, Loader=yaml.SafeLoader)`, "app.py", "python");
  });
  it("flags PHP unserialize()", () => {
    expectRuleId(unsafeDeserializationRule, `$obj = unserialize($_COOKIE['data']);`, "unsafe-deserialization-php-unserialize", "app.php", "php");
  });
});
