-- ============================================================================
-- Seed data: the skill catalog. This is reference content the product
-- requires to function (every lesson/lab/quiz/CTF challenge attaches to one
-- of these skills), not test fixture data -- analogous to seeding a
-- countries or currencies table. Admins can add more via the CMS later;
-- this is the baseline set from the product spec.
-- ============================================================================

INSERT INTO public.skill_categories (slug, name, sort_order) VALUES
  ('fundamentals', 'Fundamentals', 0),
  ('identity-access', 'Identity & Access', 1),
  ('web-vulnerabilities', 'Web Vulnerabilities', 2),
  ('api-cloud-container', 'API, Cloud & Container Security', 3),
  ('systems-network', 'Systems & Network', 4),
  ('investigation', 'OSINT & Investigation', 5),
  ('secure-engineering', 'Secure Engineering', 6),
  ('detection-response', 'Detection & Response', 7);

INSERT INTO public.skills (slug, name, category_id, description)
SELECT v.slug, v.name, c.id, v.description
FROM (VALUES
  ('http', 'HTTP', 'fundamentals', 'The HTTP request/response model, methods, headers, status codes, and caching.'),
  ('dns', 'DNS', 'fundamentals', 'Domain name resolution, record types, and how DNS is abused in attacks.'),
  ('tcp-ip', 'TCP/IP', 'fundamentals', 'The TCP/IP stack, ports, sockets, and how network traffic actually moves.'),
  ('linux', 'Linux', 'fundamentals', 'Linux filesystems, permissions, processes, and administration fundamentals.'),
  ('windows', 'Windows', 'fundamentals', 'Windows internals, Active Directory basics, and administration fundamentals.'),

  ('authentication', 'Authentication', 'identity-access', 'Verifying identity: credentials, MFA, and common authentication failures.'),
  ('authorization', 'Authorization', 'identity-access', 'Enforcing what an authenticated identity is allowed to do.'),
  ('session-security', 'Session Security', 'identity-access', 'Session tokens, fixation, hijacking, and secure session management.'),
  ('oauth-oidc', 'OAuth / OIDC Security', 'identity-access', 'Delegated authorization flows and their common misconfigurations.'),
  ('jwt-security', 'JWT Security', 'identity-access', 'JSON Web Token structure, validation pitfalls, and signing attacks.'),
  ('privilege-escalation', 'Privilege Escalation', 'identity-access', 'Moving from limited access to elevated access, on hosts and in apps.'),

  ('sql-injection', 'SQL Injection', 'web-vulnerabilities', 'Injecting attacker-controlled input into SQL queries.'),
  ('xss', 'Cross-Site Scripting (XSS)', 'web-vulnerabilities', 'Injecting attacker-controlled script into a victim''s browser context.'),
  ('csrf', 'CSRF', 'web-vulnerabilities', 'Forcing an authenticated browser to perform an unwanted action.'),
  ('ssrf', 'SSRF', 'web-vulnerabilities', 'Coercing a server into making requests to unintended destinations.'),
  ('ssti', 'SSTI', 'web-vulnerabilities', 'Server-Side Template Injection leading to code execution.'),
  ('command-injection', 'Command Injection', 'web-vulnerabilities', 'Injecting attacker-controlled input into an OS command.'),
  ('path-traversal', 'Path Traversal', 'web-vulnerabilities', 'Escaping an intended directory to read or write arbitrary files.'),
  ('idor', 'IDOR', 'web-vulnerabilities', 'Insecure Direct Object References: accessing another user''s data by ID.'),
  ('file-upload-security', 'File Upload Security', 'web-vulnerabilities', 'Preventing malicious file uploads from becoming code execution.'),

  ('api-security', 'API Security', 'api-cloud-container', 'Securing REST/GraphQL APIs against broken auth, rate limits, and mass assignment.'),
  ('cloud-security', 'Cloud Security', 'api-cloud-container', 'IAM, storage, and network misconfigurations in cloud environments.'),
  ('container-security', 'Container Security', 'api-cloud-container', 'Container isolation, image security, and orchestration misconfigurations.'),
  ('secrets-management', 'Secrets Management', 'api-cloud-container', 'Storing, rotating, and avoiding exposure of credentials and keys.'),

  ('enumeration', 'Enumeration', 'systems-network', 'Systematically discovering hosts, services, and attack surface.'),
  ('network-security', 'Network Security', 'systems-network', 'Segmentation, firewalls, and securing traffic between systems.'),
  ('cryptography-concepts', 'Cryptography Concepts', 'systems-network', 'Encryption, hashing, signing, and common cryptographic mistakes.'),

  ('osint', 'OSINT', 'investigation', 'Gathering and correlating information from publicly available sources.'),
  ('digital-forensics', 'Digital Forensics', 'investigation', 'Recovering and analyzing evidence from systems and files.'),
  ('incident-investigation', 'Incident Investigation', 'investigation', 'Reconstructing what happened during a security incident.'),
  ('evidence-handling', 'Evidence Handling', 'investigation', 'Preserving and documenting evidence so findings hold up to scrutiny.'),

  ('secure-coding', 'Secure Coding', 'secure-engineering', 'Writing code that resists common vulnerability classes by default.'),
  ('threat-modeling', 'Threat Modeling', 'secure-engineering', 'Systematically identifying and prioritizing risks before they''re exploited.'),
  ('vulnerability-analysis', 'Vulnerability Analysis', 'secure-engineering', 'Assessing the real exploitability and impact of a finding.'),
  ('remediation', 'Remediation', 'secure-engineering', 'Fixing a vulnerability correctly, not just suppressing its symptom.'),
  ('security-documentation', 'Security Documentation', 'secure-engineering', 'Writing findings and reports that a reader can act on.'),

  ('detection-engineering', 'Detection Engineering', 'detection-response', 'Building detections that reliably catch real attacker behavior.'),
  ('incident-response', 'Incident Response', 'detection-response', 'Responding to, containing, and recovering from a security incident.')
) AS v(slug, name, category_slug, description)
JOIN public.skill_categories c ON c.slug = v.category_slug;
