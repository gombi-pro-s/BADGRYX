import type { EnvironmentSpec } from "../spec";

/** A small, realistic lab environment used across the interpreter tests -- not a toy example, but not a full lab either: enough surface to exercise every command against real nested paths. */
export const fixtureSpec: EnvironmentSpec = {
  hostname: "web01",
  initial_cwd: "/home/user",
  initial_user: "user",
  users: ["user", "root"],
  sudo_rules: [{ user: "user", allowed: ["cat"] }],
  reachable_hosts: [],
  hosts: {},
  filesystem: {
    "/home/user": { type: "dir", owner: "user", perms: "rwxr-xr-x" },
    "/home/user/notes.txt": {
      type: "file",
      content: "TODO: rotate the backup credentials\nask admin about the staging DB",
      owner: "user",
      perms: "rw-r--r--",
    },
    "/home/user/.bash_history": {
      type: "file",
      content: "ssh admin@10.0.0.5\ncat /var/backups/db.sql | grep password",
      owner: "user",
      perms: "rw-------",
    },
    "/var/backups/db.sql": {
      type: "file",
      content: "-- dump\nINSERT INTO users (username, password) VALUES ('admin', 'hunter2');\n-- end",
      owner: "root",
      perms: "rw-r--r--",
    },
    "/root/flag.txt": { type: "file", content: "ICOREPEN{root_access_confirmed}", owner: "root", perms: "rw-------" },
    "/tmp": { type: "dir", owner: "root", perms: "rwxrwxrwt" },
  },
};

/**
 * A small "Cyber Range" -- two networked hosts -- used by cyber-range.test.ts.
 * `web01` (the entry host) can reach `db01` over the network, but `db01` is
 * not reachable from anywhere else, and its own credentials only work
 * against it, not against `web01` -- exercising real network-topology and
 * credential-isolation enforcement, not just "any host reaches any host."
 */
export const cyberRangeSpec: EnvironmentSpec = {
  hostname: "web01",
  initial_cwd: "/home/user",
  initial_user: "user",
  users: ["user", "root"],
  sudo_rules: [],
  reachable_hosts: ["db01"],
  hosts: {
    db01: {
      hostname: "db01",
      initial_cwd: "/home/dbadmin",
      users: ["dbadmin", "root"],
      sudo_rules: [],
      credentials: [{ user: "dbadmin", password: "S3cur3DbPass!" }],
      reachable_hosts: [],
      filesystem: {
        "/home/dbadmin": { type: "dir", owner: "dbadmin", perms: "rwxr-xr-x" },
        "/home/dbadmin/flag.txt": {
          type: "file",
          content: "ICOREPEN{lateral_movement_via_leaked_db_credentials}",
          owner: "dbadmin",
          perms: "rw-------",
        },
      },
    },
  },
  filesystem: {
    "/home/user": { type: "dir", owner: "user", perms: "rwxr-xr-x" },
    "/home/user/db-backup.conf": {
      type: "file",
      content: "# scheduled by cron, do not edit\nhost=db01\nuser=dbadmin\npassword=S3cur3DbPass!\n",
      owner: "user",
      perms: "rw-r--r--",
    },
  },
};
