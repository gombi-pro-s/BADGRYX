import type { EnvironmentSpec } from "../spec";

/** A small, realistic lab environment used across the interpreter tests -- not a toy example, but not a full lab either: enough surface to exercise every command against real nested paths. */
export const fixtureSpec: EnvironmentSpec = {
  hostname: "web01",
  initial_cwd: "/home/user",
  initial_user: "user",
  users: ["user", "root"],
  sudo_rules: [{ user: "user", allowed: ["cat"] }],
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
      perms: "rw-------",
    },
    "/root/flag.txt": { type: "file", content: "ICOREPEN{root_access_confirmed}", owner: "root", perms: "rw-------" },
    "/tmp": { type: "dir", owner: "root", perms: "rwxrwxrwt" },
  },
};
