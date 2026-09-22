-- ============================================================================
-- Seed one complete real terminal-enabled lab end to end, the same way
-- 20260921000014_seed_sample_content.sql proved the grading pipeline with a
-- real SQL injection lab: a genuine, well-known privilege-escalation
-- technique (an unrestricted sudo rule on a file-reading command --
-- documented in GTFOBins as a real-world misconfiguration, not an
-- invented puzzle), with a virtual filesystem where the flag is only
-- discoverable by actually running the right commands (sudo -l, then sudo
-- cat), not by reading page source.
-- ============================================================================

DO $outer$
DECLARE
  v_lab_id uuid;
  v_linux_skill_id uuid;
  v_privesc_skill_id uuid;
BEGIN
  SELECT id INTO v_linux_skill_id FROM public.skills WHERE slug = 'linux';
  SELECT id INTO v_privesc_skill_id FROM public.skills WHERE slug = 'privilege-escalation';

  INSERT INTO public.labs (
    slug, title, description, category, difficulty, objectives, estimated_minutes, points, published
  ) VALUES (
    'linux-privesc-sudo-cat', 'Linux Privilege Escalation: Misconfigured Sudo',
    'You have a low-privilege shell on webserver01. A sudo misconfiguration lets you read files as root without a password -- find it in a real terminal and use it to read a file only root can normally see.',
    'linux', 'easy',
    '["Enumerate what commands you can run with sudo", "Recognize why an unrestricted sudo rule on a file-reading command is a privilege escalation vector", "Use it to read a root-owned file"]'::jsonb,
    20, 100, true
  )
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_skills (lab_id, skill_id) VALUES
    (v_lab_id, v_linux_skill_id),
    (v_lab_id, v_privesc_skill_id);

  INSERT INTO public.lab_hints (lab_id, level, content, point_cost) VALUES
    (v_lab_id, 1, 'Check your current privileges, and what you''re allowed to run as another user.', 0),
    (v_lab_id, 2, '`sudo -l` lists the exact commands you''re permitted to run as root without a password.', 5),
    (v_lab_id, 3, 'If a plain file-reading command like `cat` is on that list, you can read ANY file on the system as root -- including ones outside your home directory.', 15);

  INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed)
  VALUES (v_lab_id, 'flag', encode(digest('ICOREPEN{sudo_c4t_1s_n0t_s4fe}', 'sha256'), 'hex'), 0);

  INSERT INTO public.lab_environments (lab_id, variant_seed, spec) VALUES (
    v_lab_id, 0,
    '{
      "hostname": "webserver01",
      "initial_cwd": "/home/user",
      "initial_user": "user",
      "users": ["user", "root"],
      "sudo_rules": [{ "user": "user", "allowed": ["cat"] }],
      "filesystem": {
        "/home/user": { "type": "dir", "owner": "user", "perms": "rwxr-xr-x" },
        "/home/user/notes.txt": {
          "type": "file", "owner": "user", "perms": "rw-r--r--",
          "content": "Reminder: check what I can run with sudo before bugging the admin about access again."
        },
        "/home/user/.bash_history": {
          "type": "file", "owner": "user", "perms": "rw-------",
          "content": "whoami\nid\nsudo -l\nls -la /root"
        },
        "/root": { "type": "dir", "owner": "root", "perms": "rwx------" },
        "/root/flag.txt": {
          "type": "file", "owner": "root", "perms": "rw-------",
          "content": "ICOREPEN{sudo_c4t_1s_n0t_s4fe}"
        }
      }
    }'::jsonb
  );
END $outer$;
