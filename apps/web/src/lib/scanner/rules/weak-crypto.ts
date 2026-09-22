import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Cryptographic Failures", url: "https://owasp.org/Top10/A02_2021-Cryptographic_Failures/" }];

function makeMatch(
  ruleId: string,
  title: string,
  content: string,
  line: number,
  explanation: string,
  remediation: string,
  secureExample?: string,
): RuleMatch {
  return {
    ruleId,
    category: "weak_cryptography",
    title,
    severity: "medium",
    confidence: "high",
    lineStart: line,
    lineEnd: line,
    evidence: getLineText(content, line),
    explanation,
    impact: "Weak or broken cryptographic primitives can be reversed, brute-forced, or forged far more cheaply than the developer likely assumed, undermining whatever the code was trying to protect (passwords, tokens, signatures).",
    remediation,
    secureExample,
    referenceLinks: REFERENCES,
    verificationStatus: "needs_review",
  };
}

export const weakCryptoRule: ScanRule = {
  id: "weak-crypto",
  category: "weak_cryptography",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { line } of findAllMatches(content, /createHash\s*\(\s*["'`]md5["'`]/gi)) {
      findings.push(makeMatch(
        "weak-crypto-md5",
        "MD5 used as a hash function",
        content, line,
        "MD5 is cryptographically broken (collisions are practical) and unsuitable for passwords, signatures, or integrity checks.",
        "Use SHA-256 or better for integrity/signing; use a dedicated password hash (bcrypt/scrypt/argon2) for passwords -- never a general-purpose hash function.",
      ));
    }

    for (const { line } of findAllMatches(content, /createHash\s*\(\s*["'`]sha1["'`]/gi)) {
      findings.push(makeMatch(
        "weak-crypto-sha1",
        "SHA-1 used as a hash function",
        content, line,
        "SHA-1 has practical collision attacks and should not be used for new integrity or signing purposes.",
        "Use SHA-256 or better.",
      ));
    }

    for (const { line } of findAllMatches(content, /hashlib\.md5\s*\(/g)) {
      findings.push(makeMatch(
        "weak-crypto-python-md5",
        "MD5 used as a hash function (Python hashlib)",
        content, line,
        "MD5 is cryptographically broken and unsuitable for passwords, signatures, or integrity checks.",
        "Use hashlib.sha256 for integrity, or passlib/bcrypt for password hashing.",
      ));
    }

    for (const { line } of findAllMatches(content, /\b(DES|RC4|ECB)\b/g)) {
      findings.push(makeMatch(
        "weak-crypto-weak-cipher",
        "Weak/legacy cipher or mode referenced (DES, RC4, or ECB)",
        content, line,
        "DES and RC4 are broken ciphers; ECB mode leaks patterns in the plaintext because identical plaintext blocks always encrypt to identical ciphertext blocks.",
        "Use AES-256 in an authenticated mode (GCM) instead.",
        "crypto.createCipheriv('aes-256-gcm', key, iv);",
      ));
    }

    for (const { line } of findAllMatches(content, /\bMath\.random\s*\(\s*\)/g)) {
      const lineText = getLineText(content, line);
      // No \b around these: security-sensitive variable names are often
      // camelCase compounds (sessionToken, authKey) where a token boundary
      // sits mid-identifier, so a strict \b...\b match would miss them.
      if (/token|secret|password|key|salt|nonce|session/i.test(lineText)) {
        findings.push(makeMatch(
          "weak-crypto-insecure-random",
          "Math.random() used to generate a security-sensitive value",
          content, line,
          "Math.random() is not a cryptographically secure random number generator -- its output can be predicted, which is disqualifying for tokens, keys, or session identifiers.",
          "Use crypto.randomBytes() (Node) or the Web Crypto API's crypto.getRandomValues() instead.",
          "crypto.randomBytes(32).toString('hex');",
        ));
      }
    }

    return findings;
  },
};
