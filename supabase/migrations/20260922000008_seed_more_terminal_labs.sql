-- ============================================================================
-- Three more real terminal-enabled labs, proving the terminal engine on
-- distinct scenarios and command patterns beyond the first seeded lab
-- (20260922000007_seed_terminal_lab.sql's sudo-based privilege escalation):
-- secrets enumeration (find/ls -la/cat), log-analysis forensics
-- (grep/wc -l), and multi-directory recursive enumeration (grep -r/find).
-- None of these require privilege escalation -- every file involved is
-- world-readable, matching real OSINT/enumeration/forensics work where the
-- skill is knowing where and how to look, not bypassing access control.
-- ============================================================================

DO $outer$
DECLARE
  v_lab_id uuid;
  v_linux_skill_id uuid;
  v_secrets_skill_id uuid;
  v_enum_skill_id uuid;
  v_forensics_skill_id uuid;
  v_incident_skill_id uuid;
  v_auth_skill_id uuid;
BEGIN
  SELECT id INTO v_linux_skill_id FROM public.skills WHERE slug = 'linux';
  SELECT id INTO v_secrets_skill_id FROM public.skills WHERE slug = 'secrets-management';
  SELECT id INTO v_enum_skill_id FROM public.skills WHERE slug = 'enumeration';
  SELECT id INTO v_forensics_skill_id FROM public.skills WHERE slug = 'digital-forensics';
  SELECT id INTO v_incident_skill_id FROM public.skills WHERE slug = 'incident-investigation';
  SELECT id INTO v_auth_skill_id FROM public.skills WHERE slug = 'authentication';

  -- ==========================================================================
  -- Lab A: Secrets Enumeration -- Find the Leaked API Key
  -- ==========================================================================
  INSERT INTO public.labs (
    slug, title, description, category, difficulty, objectives, estimated_minutes, points, published
  ) VALUES (
    'secrets-enum-leaked-key', 'Secrets Enumeration: Find the Leaked API Key',
    'A developer left a backup of their .env file on a production web server. You have a shell -- find where credentials tend to leak (backup files, forgotten config copies) and extract the real key.',
    'linux', 'easy',
    '["Enumerate a filesystem for accidentally-exposed backup/config files", "Distinguish a real secret from decoy configuration", "Explain why backup files and .bak/.backup copies are a common leak vector"]'::jsonb,
    20, 100, true
  )
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_skills (lab_id, skill_id) VALUES
    (v_lab_id, v_linux_skill_id), (v_lab_id, v_secrets_skill_id), (v_lab_id, v_enum_skill_id);

  INSERT INTO public.lab_hints (lab_id, level, content, point_cost) VALUES
    (v_lab_id, 1, 'Start by looking around the web application''s directory. `ls -la` shows hidden files (dotfiles) that a plain `ls` won''t.', 0),
    (v_lab_id, 2, 'Developers often leave a backup copy of a config file next to the original -- look for names ending in .backup, .bak, or ~.', 5),
    (v_lab_id, 3, '`find /var/www -name "*.backup"` will locate it directly instead of browsing by hand.', 15);

  INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed)
  VALUES (v_lab_id, 'flag', encode(digest('ICOREPEN{f0und_th3_l34ked_k3y}', 'sha256'), 'hex'), 0);

  INSERT INTO public.lab_environments (lab_id, variant_seed, spec) VALUES (
    v_lab_id, 0,
    '{
      "hostname": "prod-web02",
      "initial_cwd": "/var/www/app",
      "initial_user": "deploy",
      "users": ["deploy", "root"],
      "sudo_rules": [],
      "filesystem": {
        "/var/www/app": { "type": "dir", "owner": "deploy", "perms": "rwxr-xr-x" },
        "/var/www/app/index.html": {
          "type": "file", "owner": "deploy", "perms": "rw-r--r--",
          "content": "<html><body>Welcome to the app</body></html>"
        },
        "/var/www/app/.env": {
          "type": "file", "owner": "deploy", "perms": "rw-------",
          "content": "STRIPE_API_KEY=sk_live_PLACEHOLDER_ROTATED\nDATABASE_URL=postgres://app:redacted@10.0.4.5/appdb"
        },
        "/var/www/app/.env.backup": {
          "type": "file", "owner": "deploy", "perms": "rw-r--r--",
          "content": "# forgotten backup from the last deploy -- rotate this if found\nAPI_KEY=ICOREPEN{f0und_th3_l34ked_k3y}\nDATABASE_URL=postgres://app:redacted@10.0.4.5/appdb"
        },
        "/var/www/app/config/database.yml": {
          "type": "file", "owner": "deploy", "perms": "rw-r--r--",
          "content": "production:\n  adapter: postgresql\n  host: 10.0.4.5\n  username: app\n  password: <set via DATABASE_URL env var>"
        }
      }
    }'::jsonb
  );

  -- ==========================================================================
  -- Lab B: Digital Forensics -- Trace the Brute-Force Attack
  -- ==========================================================================
  INSERT INTO public.labs (
    slug, title, description, category, difficulty, objectives, estimated_minutes, points, published
  ) VALUES (
    'forensics-auth-log-bruteforce', 'Digital Forensics: Trace the Brute-Force Attack',
    'A server''s SSH auth log is full of failed login attempts -- but one of them succeeded. Find the single successful login buried in the noise and pull the session detail it left behind.',
    'forensics', 'medium',
    '["Read and filter a real authentication log for a specific event among noise", "Distinguish failed vs. successful authentication log entries", "Use grep to filter signal from a large volume of log lines instead of reading them all"]'::jsonb,
    25, 150, true
  )
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_skills (lab_id, skill_id) VALUES
    (v_lab_id, v_forensics_skill_id), (v_lab_id, v_incident_skill_id), (v_lab_id, v_auth_skill_id);

  INSERT INTO public.lab_hints (lab_id, level, content, point_cost) VALUES
    (v_lab_id, 1, 'Check how many lines are actually in the log first (`wc -l`) before deciding to read it top to bottom.', 0),
    (v_lab_id, 2, 'Almost every line says "Failed password". You only care about the one that doesn''t.', 5),
    (v_lab_id, 3, '`grep Accepted /var/log/auth.log` filters straight to the line that matters.', 15);

  INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed)
  VALUES (v_lab_id, 'flag', encode(digest('ICOREPEN{n33dle_1n_th3_l0g_haystack}', 'sha256'), 'hex'), 0);

  INSERT INTO public.lab_environments (lab_id, variant_seed, spec) VALUES (
    v_lab_id, 0,
    '{
      "hostname": "bastion01",
      "initial_cwd": "/var/log",
      "initial_user": "analyst",
      "users": ["analyst", "root"],
      "sudo_rules": [],
      "filesystem": {
        "/var/log/auth.log": {
          "type": "file", "owner": "root", "perms": "rw-r--r--",
          "content": "Jan 14 03:01:02 bastion01 sshd[1021]: Failed password for invalid user admin from 198.51.100.23 port 40112 ssh2\nJan 14 03:01:05 bastion01 sshd[1022]: Failed password for invalid user test from 198.51.100.23 port 40114 ssh2\nJan 14 03:01:09 bastion01 sshd[1023]: Failed password for root from 198.51.100.23 port 40116 ssh2\nJan 14 03:01:13 bastion01 sshd[1024]: Failed password for invalid user oracle from 198.51.100.23 port 40118 ssh2\nJan 14 03:01:18 bastion01 sshd[1025]: Failed password for invalid user postgres from 198.51.100.23 port 40120 ssh2\nJan 14 03:01:22 bastion01 sshd[1026]: Failed password for invalid user ubuntu from 198.51.100.23 port 40122 ssh2\nJan 14 03:01:27 bastion01 sshd[1027]: Failed password for admin from 198.51.100.23 port 40124 ssh2\nJan 14 03:01:31 bastion01 sshd[1028]: Failed password for admin from 198.51.100.23 port 40126 ssh2\nJan 14 03:01:36 bastion01 sshd[1029]: Failed password for admin from 198.51.100.23 port 40128 ssh2\nJan 14 03:01:41 bastion01 sshd[1030]: Accepted password for admin from 198.51.100.23 port 40130 ssh2 -- session ICOREPEN{n33dle_1n_th3_l0g_haystack}\nJan 14 03:02:03 bastion01 sshd[1031]: Failed password for invalid user guest from 203.0.113.9 port 51002 ssh2\nJan 14 03:02:08 bastion01 sshd[1032]: Failed password for invalid user demo from 203.0.113.9 port 51004 ssh2\nJan 14 03:02:14 bastion01 sshd[1033]: Failed password for invalid user backup from 203.0.113.9 port 51006 ssh2\nJan 14 03:02:19 bastion01 sshd[1034]: Failed password for invalid user ftpuser from 203.0.113.9 port 51008 ssh2"
        }
      }
    }'::jsonb
  );

  -- ==========================================================================
  -- Lab C: Enumeration -- Find the Outdated Service
  -- ==========================================================================
  INSERT INTO public.labs (
    slug, title, description, category, difficulty, objectives, estimated_minutes, points, published
  ) VALUES (
    'enum-outdated-service', 'Enumeration: Find the Outdated Service',
    'A host runs several internal services. One of them is years out of date and long overdue for patching. Enumerate what''s installed and find it.',
    'linux', 'easy',
    '["Systematically enumerate multiple services/directories rather than guessing", "Use recursive search to find a specific string across many files at once", "Recognize an end-of-life software version as a real risk indicator"]'::jsonb,
    20, 100, true
  )
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_skills (lab_id, skill_id) VALUES
    (v_lab_id, v_enum_skill_id), (v_lab_id, v_linux_skill_id);

  INSERT INTO public.lab_hints (lab_id, level, content, point_cost) VALUES
    (v_lab_id, 1, 'Every installed service has a version file under /opt/services/<name>/. Start by listing what''s there.', 0),
    (v_lab_id, 2, 'Rather than opening every version file by hand, search across all of them at once for a word like "EOL" or "CRITICAL".', 5),
    (v_lab_id, 3, '`grep -r EOL /opt/services` finds the outdated one directly; check that service''s directory for more.', 15);

  INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed)
  VALUES (v_lab_id, 'flag', encode(digest('ICOREPEN{0utd4ted_s3rv1c3_f0und}', 'sha256'), 'hex'), 0);

  INSERT INTO public.lab_environments (lab_id, variant_seed, spec) VALUES (
    v_lab_id, 0,
    '{
      "hostname": "internal-svc03",
      "initial_cwd": "/opt/services",
      "initial_user": "svc",
      "users": ["svc", "root"],
      "sudo_rules": [],
      "filesystem": {
        "/opt/services/webapp/version.txt": { "type": "file", "owner": "svc", "perms": "rw-r--r--", "content": "webapp v3.2.1 (current)" },
        "/opt/services/cache/version.txt": { "type": "file", "owner": "svc", "perms": "rw-r--r--", "content": "cache-node v6.0.9 (current)" },
        "/opt/services/metrics/version.txt": { "type": "file", "owner": "svc", "perms": "rw-r--r--", "content": "metrics-agent v2.1.0 (current)" },
        "/opt/services/authgateway/version.txt": {
          "type": "file", "owner": "svc", "perms": "rw-r--r--",
          "content": "authgateway v1.0.4 (EOL 2019 -- CRITICAL: upgrade immediately, no longer receives security patches)"
        },
        "/opt/services/authgateway/NOTES.txt": {
          "type": "file", "owner": "svc", "perms": "rw-r--r--",
          "content": "Ticket #4521: still haven''t patched authgateway, keeps getting deprioritized.\nFlag for whoever actually finds this: ICOREPEN{0utd4ted_s3rv1c3_f0und}"
        }
      }
    }'::jsonb
  );
END $outer$;
