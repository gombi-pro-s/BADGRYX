-- ============================================================================
-- One real "Cyber Range" lab proving the multi-host terminal engine
-- (lib/terminal/spec.ts's `hosts`/`reachable_hosts`/`credentials`, ADR
-- 0023): two networked hosts, a real leaked credential the learner must
-- find before they can pivot, and a flag that only exists on the second
-- host -- unreachable without a successful `ssh`.
-- ============================================================================

DO $outer$
DECLARE
  v_lab_id uuid;
  v_linux_skill_id uuid;
  v_network_skill_id uuid;
  v_secrets_skill_id uuid;
  v_enum_skill_id uuid;
BEGIN
  SELECT id INTO v_linux_skill_id FROM public.skills WHERE slug = 'linux';
  SELECT id INTO v_network_skill_id FROM public.skills WHERE slug = 'network-security';
  SELECT id INTO v_secrets_skill_id FROM public.skills WHERE slug = 'secrets-management';
  SELECT id INTO v_enum_skill_id FROM public.skills WHERE slug = 'enumeration';

  INSERT INTO public.labs (
    slug, title, description, category, difficulty, objectives, estimated_minutes, points, published
  ) VALUES (
    'cyber-range-lateral-movement-db', 'Cyber Range: Lateral Movement to the Database Host',
    'You have a shell on a web application server. It isn''t the target -- a database host on the same network is. Find a real credential leaked on this host, then use it to pivot laterally with ssh.',
    'linux', 'medium',
    '["Enumerate a host for credentials that grant access elsewhere on the network", "Use ssh to pivot from one host to another with a found credential", "Recognize a scheduled backup/config file as a common lateral-movement leak vector"]'::jsonb,
    25, 175, true
  )
  RETURNING id INTO v_lab_id;

  INSERT INTO public.lab_skills (lab_id, skill_id) VALUES
    (v_lab_id, v_linux_skill_id), (v_lab_id, v_network_skill_id),
    (v_lab_id, v_secrets_skill_id), (v_lab_id, v_enum_skill_id);

  INSERT INTO public.lab_hints (lab_id, level, content, point_cost) VALUES
    (v_lab_id, 1, 'This host isn''t the only one on the network. Look for anything that references another host -- a cron job''s config file is a common place to find one.', 0),
    (v_lab_id, 2, '`cat /etc/cron.d/db-backup.conf` has a hostname, a username, and a password in it. That''s everything `ssh` needs.', 10),
    (v_lab_id, 3, '`ssh dbadmin@db-prod01 <the password from the config>` connects you to the database host directly -- the flag is somewhere in dbadmin''s home directory there.', 20);

  INSERT INTO public.lab_flags (lab_id, label, flag_hash, variant_seed)
  VALUES (v_lab_id, 'flag', encode(digest('ICOREPEN{p1v0ted_v1a_l34ked_backup_cred5}', 'sha256'), 'hex'), 0);

  INSERT INTO public.lab_environments (lab_id, variant_seed, spec) VALUES (
    v_lab_id, 0,
    '{
      "hostname": "web-app03",
      "initial_cwd": "/home/appuser",
      "initial_user": "appuser",
      "users": ["appuser", "root"],
      "sudo_rules": [],
      "reachable_hosts": ["db-prod01"],
      "filesystem": {
        "/home/appuser": { "type": "dir", "owner": "appuser", "perms": "rwxr-xr-x" },
        "/home/appuser/README.txt": {
          "type": "file", "owner": "appuser", "perms": "rw-r--r--",
          "content": "This host only serves the frontend. Application data lives on the database tier."
        },
        "/etc/cron.d/db-backup.conf": {
          "type": "file", "owner": "root", "perms": "rw-r--r--",
          "content": "# nightly backup job -- do not edit, managed by ops\n# target: db-prod01\n0 2 * * * appuser /usr/local/bin/backup-db.sh --host=db-prod01 --user=dbadmin --password=Tr0pic4l-Storm-91\n"
        }
      },
      "hosts": {
        "db-prod01": {
          "hostname": "db-prod01",
          "initial_cwd": "/home/dbadmin",
          "users": ["dbadmin", "root"],
          "sudo_rules": [],
          "reachable_hosts": [],
          "credentials": [{ "user": "dbadmin", "password": "Tr0pic4l-Storm-91" }],
          "filesystem": {
            "/home/dbadmin": { "type": "dir", "owner": "dbadmin", "perms": "rwxr-xr-x" },
            "/home/dbadmin/flag.txt": {
              "type": "file", "owner": "dbadmin", "perms": "rw-------",
              "content": "ICOREPEN{p1v0ted_v1a_l34ked_backup_cred5}"
            },
            "/home/dbadmin/notes.txt": {
              "type": "file", "owner": "dbadmin", "perms": "rw-r--r--",
              "content": "TODO: rotate the backup script credential, it has been the same for two years."
            }
          }
        }
      }
    }'::jsonb
  );
END $outer$;
