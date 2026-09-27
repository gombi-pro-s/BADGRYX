import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { environmentSpecSchema, initialTerminalState } from "../spec";

/**
 * The exact environment spec seeded for "Cyber Range: Lateral Movement to
 * the Database Host" (cyber-range-lateral-movement-db, see
 * supabase/migrations/20260922000027_seed_cyber_range_lab.sql). Kept in
 * sync by hand, same as the other seeded-lab-*.test.ts files.
 */
const seededSpecJson = {
  hostname: "web-app03",
  initial_cwd: "/home/appuser",
  initial_user: "appuser",
  users: ["appuser", "root"],
  sudo_rules: [],
  reachable_hosts: ["db-prod01"],
  filesystem: {
    "/home/appuser": { type: "dir", owner: "appuser", perms: "rwxr-xr-x" },
    "/home/appuser/README.txt": {
      type: "file",
      owner: "appuser",
      perms: "rw-r--r--",
      content: "This host only serves the frontend. Application data lives on the database tier.",
    },
    "/etc/cron.d/db-backup.conf": {
      type: "file",
      owner: "root",
      perms: "rw-r--r--",
      content:
        "# nightly backup job -- do not edit, managed by ops\n# target: db-prod01\n0 2 * * * appuser /usr/local/bin/backup-db.sh --host=db-prod01 --user=dbadmin --password=Tr0pic4l-Storm-91\n",
    },
  },
  hosts: {
    "db-prod01": {
      hostname: "db-prod01",
      initial_cwd: "/home/dbadmin",
      users: ["dbadmin", "root"],
      sudo_rules: [],
      reachable_hosts: [],
      credentials: [{ user: "dbadmin", password: "Tr0pic4l-Storm-91" }],
      filesystem: {
        "/home/dbadmin": { type: "dir", owner: "dbadmin", perms: "rwxr-xr-x" },
        "/home/dbadmin/flag.txt": {
          type: "file",
          owner: "dbadmin",
          perms: "rw-------",
          content: "ICOREPEN{p1v0ted_v1a_l34ked_backup_cred5}",
        },
        "/home/dbadmin/notes.txt": {
          type: "file",
          owner: "dbadmin",
          perms: "rw-r--r--",
          content: "TODO: rotate the backup script credential, it has been the same for two years.",
        },
      },
    },
  },
};

describe("seeded lab: cyber-range-lateral-movement-db", () => {
  it("the spec validates against the schema", () => {
    expect(environmentSpecSchema.safeParse(seededSpecJson).success).toBe(true);
  });

  it("is solvable: cat the cron config leaks the ssh credential, ssh pivots, cat gets the flag", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    let state = initialTerminalState(spec);

    let result = executeCommand(spec, state, "cat /etc/cron.d/db-backup.conf");
    expect(result.output).toContain("--user=dbadmin");
    expect(result.output).toContain("--password=Tr0pic4l-Storm-91");
    state = result.state;

    result = executeCommand(spec, state, "ssh dbadmin@db-prod01 Tr0pic4l-Storm-91");
    expect(result.output).toBe("Welcome to db-prod01.");
    expect(result.state.host).toBe("db-prod01");
    state = result.state;

    result = executeCommand(spec, state, "cat flag.txt");
    expect(result.output).toBe("ICOREPEN{p1v0ted_v1a_l34ked_backup_cred5}");
  });

  it("the flag is genuinely unreachable from web-app03 without pivoting", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    const result = executeCommand(spec, state, "cat /home/dbadmin/flag.txt");
    expect(result.output).not.toContain("ICOREPEN");
  });

  it("guessing the password wrong is genuinely rejected, not a soft warning", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    const result = executeCommand(spec, state, "ssh dbadmin@db-prod01 wrong-guess");
    expect(result.output).toBe("dbadmin@db-prod01: Permission denied (publickey,password).");
    expect(result.state.host).toBe("web-app03");
  });
});
