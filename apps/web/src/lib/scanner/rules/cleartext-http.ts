import type { RuleMatch, ScanRule } from "./types";
import { findAllMatches, getLineText } from "./util";

const REFERENCES = [{ title: "OWASP: Cryptographic Failures (cleartext transmission)", url: "https://owasp.org/Top10/A02_2021-Cryptographic_Failures/" }];

const LOCAL_HOSTS = /^https?:\/\/(localhost|127\.0\.0\.1|0\.0\.0\.0|::1|example\.(com|org|net))([:/]|$)/i;
const XML_NAMESPACE = /^https?:\/\/(www\.w3\.org|schemas\.|xmlns\.)/i;

export const cleartextHttpRule: ScanRule = {
  id: "cleartext-http",
  category: "cleartext_http",
  run(file) {
    const { content } = file;
    const findings: RuleMatch[] = [];

    for (const { match, line } of findAllMatches(content, /["'`]http:\/\/[^\s"'`]+["'`]/g)) {
      const url = match[0].slice(1, -1);
      if (LOCAL_HOSTS.test(url) || XML_NAMESPACE.test(url)) continue;

      const hasCredentials = /:\/\/[^/]+:[^/@]+@/.test(url);
      findings.push({
        ruleId: "cleartext-http-hardcoded-url",
        category: "cleartext_http",
        title: hasCredentials ? "Credentials embedded in a plaintext HTTP URL" : "Hardcoded plaintext HTTP URL",
        severity: hasCredentials ? "high" : "low",
        confidence: "medium",
        lineStart: line,
        lineEnd: line,
        evidence: getLineText(content, line),
        explanation: hasCredentials
          ? "A URL embeds a username/password and uses unencrypted HTTP, so those credentials travel in plaintext and are visible to anyone on the network path."
          : "A hardcoded URL uses unencrypted HTTP rather than HTTPS.",
        impact: "Traffic to this URL (including any tokens, cookies, or request/response bodies) can be read or tampered with by anyone able to observe the network path (a shared Wi-Fi network, a compromised router, an ISP).",
        remediation: "Use https:// for any endpoint that isn't purely local development, and never place credentials directly in a URL.",
        referenceLinks: REFERENCES,
        verificationStatus: "needs_review",
      });
    }

    return findings;
  },
};
