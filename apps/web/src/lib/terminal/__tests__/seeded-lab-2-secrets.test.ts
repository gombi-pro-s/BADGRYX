import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { environmentSpecSchema, initialTerminalState } from "../spec";

/**
 * The exact environment spec seeded for "Secrets Enumeration: Find the
 * Leaked API Key" (secrets-enum-leaked-key, see
 * supabase/migrations/20260922000008_seed_more_terminal_labs.sql). Kept in
 * sync by hand, same as seeded-lab.test.ts.
 */
const seededSpecJson = {
  hostname: "prod-web02",
  initial_cwd: "/var/www/app",
  initial_user: "deploy",
  users: ["deploy", "root"],
  sudo_rules: [],
  filesystem: {
    "/var/www/app": { type: "dir", owner: "deploy", perms: "rwxr-xr-x" },
    "/var/www/app/index.html": {
      type: "file",
      owner: "deploy",
      perms: "rw-r--r--",
      content: "<html><body>Welcome to the app</body></html>",
    },
    "/var/www/app/.env": {
      type: "file",
      owner: "deploy",
      perms: "rw-------",
      content: "STRIPE_API_KEY=sk_live_PLACEHOLDER_ROTATED\nDATABASE_URL=postgres://app:redacted@10.0.4.5/appdb",
    },
    "/var/www/app/.env.backup": {
      type: "file",
      owner: "deploy",
      perms: "rw-r--r--",
      content: "# forgotten backup from the last deploy -- rotate this if found\nAPI_KEY=ICOREPEN{f0und_th3_l34ked_k3y}\nDATABASE_URL=postgres://app:redacted@10.0.4.5/appdb",
    },
    "/var/www/app/config/database.yml": {
      type: "file",
      owner: "deploy",
      perms: "rw-r--r--",
      content: "production:\n  adapter: postgresql\n  host: 10.0.4.5\n  username: app\n  password: <set via DATABASE_URL env var>",
    },
  },
};

describe("seeded lab: secrets-enum-leaked-key", () => {
  it("the spec validates against the schema", () => {
    expect(environmentSpecSchema.safeParse(seededSpecJson).success).toBe(true);
  });

  it("is solvable: ls -la reveals the dotfiles, find locates the backup, cat reveals the real key", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    let state = initialTerminalState(spec);

    let result = executeCommand(spec, state, "ls -la");
    expect(result.output).toContain(".env.backup");
    state = result.state;

    result = executeCommand(spec, state, 'find /var/www -name "*.backup"');
    expect(result.output).toBe("/var/www/app/.env.backup");
    state = result.state;

    result = executeCommand(spec, state, "cat .env.backup");
    expect(result.output).toContain("ICOREPEN{f0und_th3_l34ked_k3y}");
  });

  it("the live .env is readable but contains only the rotated (decoy) key, not the flag -- the lesson is that the forgotten backup, not permissions, is the real leak", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    const result = executeCommand(spec, state, "cat .env");
    expect(result.output).toContain("PLACEHOLDER_ROTATED");
    expect(result.output).not.toContain("ICOREPEN");
  });

  it("the database.yml decoy does not contain the flag", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    const result = executeCommand(spec, state, "cat config/database.yml");
    expect(result.output).not.toContain("ICOREPEN");
  });
});
