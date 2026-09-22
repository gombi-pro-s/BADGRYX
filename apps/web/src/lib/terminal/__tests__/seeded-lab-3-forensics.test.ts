import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { environmentSpecSchema, initialTerminalState } from "../spec";

/**
 * The exact environment spec seeded for "Digital Forensics: Trace the
 * Brute-Force Attack" (forensics-auth-log-bruteforce, see
 * supabase/migrations/20260922000008_seed_more_terminal_labs.sql).
 */
const AUTH_LOG_CONTENT =
  "Jan 14 03:01:02 bastion01 sshd[1021]: Failed password for invalid user admin from 198.51.100.23 port 40112 ssh2\n" +
  "Jan 14 03:01:05 bastion01 sshd[1022]: Failed password for invalid user test from 198.51.100.23 port 40114 ssh2\n" +
  "Jan 14 03:01:09 bastion01 sshd[1023]: Failed password for root from 198.51.100.23 port 40116 ssh2\n" +
  "Jan 14 03:01:13 bastion01 sshd[1024]: Failed password for invalid user oracle from 198.51.100.23 port 40118 ssh2\n" +
  "Jan 14 03:01:18 bastion01 sshd[1025]: Failed password for invalid user postgres from 198.51.100.23 port 40120 ssh2\n" +
  "Jan 14 03:01:22 bastion01 sshd[1026]: Failed password for invalid user ubuntu from 198.51.100.23 port 40122 ssh2\n" +
  "Jan 14 03:01:27 bastion01 sshd[1027]: Failed password for admin from 198.51.100.23 port 40124 ssh2\n" +
  "Jan 14 03:01:31 bastion01 sshd[1028]: Failed password for admin from 198.51.100.23 port 40126 ssh2\n" +
  "Jan 14 03:01:36 bastion01 sshd[1029]: Failed password for admin from 198.51.100.23 port 40128 ssh2\n" +
  "Jan 14 03:01:41 bastion01 sshd[1030]: Accepted password for admin from 198.51.100.23 port 40130 ssh2 -- session ICOREPEN{n33dle_1n_th3_l0g_haystack}\n" +
  "Jan 14 03:02:03 bastion01 sshd[1031]: Failed password for invalid user guest from 203.0.113.9 port 51002 ssh2\n" +
  "Jan 14 03:02:08 bastion01 sshd[1032]: Failed password for invalid user demo from 203.0.113.9 port 51004 ssh2\n" +
  "Jan 14 03:02:14 bastion01 sshd[1033]: Failed password for invalid user backup from 203.0.113.9 port 51006 ssh2\n" +
  "Jan 14 03:02:19 bastion01 sshd[1034]: Failed password for invalid user ftpuser from 203.0.113.9 port 51008 ssh2";

const seededSpecJson = {
  hostname: "bastion01",
  initial_cwd: "/var/log",
  initial_user: "analyst",
  users: ["analyst", "root"],
  sudo_rules: [],
  filesystem: {
    "/var/log/auth.log": { type: "file", owner: "root", perms: "rw-r--r--", content: AUTH_LOG_CONTENT },
  },
};

describe("seeded lab: forensics-auth-log-bruteforce", () => {
  it("the spec validates against the schema", () => {
    expect(environmentSpecSchema.safeParse(seededSpecJson).success).toBe(true);
  });

  it("is solvable: wc -l shows the volume, grep Accepted isolates the one real login with the flag", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    let state = initialTerminalState(spec);

    let result = executeCommand(spec, state, "wc -l auth.log");
    expect(result.output).toBe("14 /var/log/auth.log");
    state = result.state;

    result = executeCommand(spec, state, "grep Accepted auth.log");
    expect(result.output).toBe(
      "Jan 14 03:01:41 bastion01 sshd[1030]: Accepted password for admin from 198.51.100.23 port 40130 ssh2 -- session ICOREPEN{n33dle_1n_th3_l0g_haystack}",
    );
  });

  it("grep -v-equivalent scanning: every other line is a Failed attempt, confirming the noise-to-signal ratio", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    const result = executeCommand(spec, state, "grep Failed auth.log");
    expect(result.output.split("\n")).toHaveLength(13);
  });
});
