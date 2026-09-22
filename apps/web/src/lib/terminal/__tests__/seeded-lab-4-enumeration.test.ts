import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { environmentSpecSchema, initialTerminalState } from "../spec";

/**
 * The exact environment spec seeded for "Enumeration: Find the Outdated
 * Service" (enum-outdated-service, see
 * supabase/migrations/20260922000008_seed_more_terminal_labs.sql).
 */
const seededSpecJson = {
  hostname: "internal-svc03",
  initial_cwd: "/opt/services",
  initial_user: "svc",
  users: ["svc", "root"],
  sudo_rules: [],
  filesystem: {
    "/opt/services/webapp/version.txt": { type: "file", owner: "svc", perms: "rw-r--r--", content: "webapp v3.2.1 (current)" },
    "/opt/services/cache/version.txt": { type: "file", owner: "svc", perms: "rw-r--r--", content: "cache-node v6.0.9 (current)" },
    "/opt/services/metrics/version.txt": { type: "file", owner: "svc", perms: "rw-r--r--", content: "metrics-agent v2.1.0 (current)" },
    "/opt/services/authgateway/version.txt": {
      type: "file",
      owner: "svc",
      perms: "rw-r--r--",
      content: "authgateway v1.0.4 (EOL 2019 -- CRITICAL: upgrade immediately, no longer receives security patches)",
    },
    "/opt/services/authgateway/NOTES.txt": {
      type: "file",
      owner: "svc",
      perms: "rw-r--r--",
      content: "Ticket #4521: still haven't patched authgateway, keeps getting deprioritized.\nFlag for whoever actually finds this: ICOREPEN{0utd4ted_s3rv1c3_f0und}",
    },
  },
};

describe("seeded lab: enum-outdated-service", () => {
  it("the spec validates against the schema", () => {
    expect(environmentSpecSchema.safeParse(seededSpecJson).success).toBe(true);
  });

  it("is solvable: recursive grep across every service finds the one that's EOL, then cat gets the flag", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    let state = initialTerminalState(spec);

    let result = executeCommand(spec, state, "grep -r EOL /opt/services");
    expect(result.output).toBe("/opt/services/authgateway/version.txt:authgateway v1.0.4 (EOL 2019 -- CRITICAL: upgrade immediately, no longer receives security patches)");
    state = result.state;

    result = executeCommand(spec, state, "find /opt/services/authgateway");
    expect(result.output.split("\n")).toContain("/opt/services/authgateway/NOTES.txt");
    state = result.state;

    result = executeCommand(spec, state, "cat /opt/services/authgateway/NOTES.txt");
    expect(result.output).toContain("ICOREPEN{0utd4ted_s3rv1c3_f0und}");
  });

  it("the other three services' version files don't mention EOL", () => {
    const spec = environmentSpecSchema.parse(seededSpecJson);
    const state = initialTerminalState(spec);
    for (const service of ["webapp", "cache", "metrics"]) {
      const result = executeCommand(spec, state, `cat /opt/services/${service}/version.txt`);
      expect(result.output).not.toContain("EOL");
    }
  });
});
