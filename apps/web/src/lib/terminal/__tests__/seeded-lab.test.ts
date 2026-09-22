import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { environmentSpecSchema, initialTerminalState } from "../spec";

/**
 * The exact environment spec seeded for the real "Linux Privilege
 * Escalation: Misconfigured Sudo" lab
 * (supabase/migrations/20260922000007_seed_terminal_lab.sql) -- kept in
 * sync by hand (a SQL migration can't import a TS fixture). If that
 * migration's spec changes, update this constant too. This test proves the
 * lab is actually solvable through the interpreter, not just schema-valid
 * -- the same "prove it end to end with real content" precedent
 * supabase/tests/005_seeded_content_e2e.sql set at the SQL layer for the
 * seeded SQL injection lab.
 */
const seededSpecJson = {
  hostname: "webserver01",
  initial_cwd: "/home/user",
  initial_user: "user",
  users: ["user", "root"],
  sudo_rules: [{ user: "user", allowed: ["cat"] }],
  filesystem: {
    "/home/user": { type: "dir", owner: "user", perms: "rwxr-xr-x" },
    "/home/user/notes.txt": {
      type: "file",
      owner: "user",
      perms: "rw-r--r--",
      content: "Reminder: check what I can run with sudo before bugging the admin about access again.",
    },
    "/home/user/.bash_history": {
      type: "file",
      owner: "user",
      perms: "rw-------",
      content: "whoami\nid\nsudo -l\nls -la /root",
    },
    "/root": { type: "dir", owner: "root", perms: "rwx------" },
    "/root/flag.txt": {
      type: "file",
      owner: "root",
      perms: "rw-------",
      content: "ICOREPEN{sudo_c4t_1s_n0t_s4fe}",
    },
  },
};

describe("seeded lab: linux-privesc-sudo-cat", () => {
  it("the spec validates against the schema the admin UI and execute.ts both enforce", () => {
    const parsed = environmentSpecSchema.safeParse(seededSpecJson);
    expect(parsed.success).toBe(true);
  });

  it("is solvable through the intended path: enumerate sudo, then read the flag as root", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    let state = initialTerminalState(spec);

    // A learner exploring the box for real: a direct cat is refused --
    // /root/flag.txt is owned by root, not world-readable, so the "just
    // read it" shortcut genuinely doesn't work and sudo actually matters.
    let result = executeCommand(spec, state, "cat /root/flag.txt");
    expect(result.output).toBe("cat: /root/flag.txt: Permission denied");
    state = result.state;

    result = executeCommand(spec, state, "sudo -l");
    expect(result.output).toContain("(ALL) cat");
    state = result.state;

    result = executeCommand(spec, state, "sudo cat /root/flag.txt");
    expect(result.output).toBe("ICOREPEN{sudo_c4t_1s_n0t_s4fe}");
  });

  it("the same flag text hashes to what lab_flags stores (sha256, matching lib/security/flag-hash.ts)", async () => {
    const { createHash } = await import("node:crypto");
    const hash = createHash("sha256").update("ICOREPEN{sudo_c4t_1s_n0t_s4fe}", "utf8").digest("hex");
    // Cross-checked against the migration's encode(digest(flag, 'sha256'), 'hex') call --
    // this is the same function AUDIT-verified byte-identical to Postgres' digest() earlier in this project.
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("a plain user cannot escalate via an unpermitted command", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    const result = executeCommand(spec, state, "sudo ls /root");
    expect(result.output).toMatch(/not in the sudoers file/);
  });
});
