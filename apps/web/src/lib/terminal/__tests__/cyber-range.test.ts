import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { initialTerminalState } from "../spec";
import { cyberRangeSpec } from "./fixture";

const start = () => initialTerminalState(cyberRangeSpec);

describe("ssh: network topology", () => {
  it("refuses to connect to a host not in reachable_hosts", () => {
    const { output, state } = executeCommand(cyberRangeSpec, start(), "ssh dbadmin@unknown-host S3cur3DbPass!");
    expect(output).toBe("ssh: connect to host unknown-host port 22: No route to host");
    expect(state.host).toBe("web01");
  });

  it("refuses a hostname that isn't declared anywhere, even if claimed reachable", () => {
    const spec = { ...cyberRangeSpec, reachable_hosts: ["ghost-host"] };
    const { output } = executeCommand(spec, start(), "ssh root@ghost-host anything");
    expect(output).toBe("ssh: Could not resolve hostname ghost-host: Name or service not known");
  });
});

describe("ssh: credentials", () => {
  it("refuses a reachable host with the wrong password", () => {
    const { output, state } = executeCommand(cyberRangeSpec, start(), "ssh dbadmin@db01 wrong-password");
    expect(output).toBe("dbadmin@db01: Permission denied (publickey,password).");
    expect(state.host).toBe("web01");
  });

  it("refuses a reachable host with a valid password for the wrong user", () => {
    const { output } = executeCommand(cyberRangeSpec, start(), "ssh root@db01 S3cur3DbPass!");
    expect(output).toBe("root@db01: Permission denied (publickey,password).");
  });

  it("succeeds with the real leaked credential found via cat", () => {
    const step1 = executeCommand(cyberRangeSpec, start(), "cat db-backup.conf");
    expect(step1.output).toContain("password=S3cur3DbPass!");

    const step2 = executeCommand(cyberRangeSpec, step1.state, "ssh dbadmin@db01 S3cur3DbPass!");
    expect(step2.output).toBe("Welcome to db01.");
    expect(step2.state.host).toBe("db01");
    expect(step2.state.user).toBe("dbadmin");
    expect(step2.state.cwd).toBe("/home/dbadmin");
  });
});

describe("ssh: pivoting actually changes which filesystem commands see", () => {
  it("cannot read the db01 flag before pivoting", () => {
    const { output } = executeCommand(cyberRangeSpec, start(), "cat /home/dbadmin/flag.txt");
    expect(output).toBe("cat: /home/dbadmin/flag.txt: No such file or directory");
  });

  it("can read the db01 flag, hostname, and pwd only after a successful ssh", () => {
    let state = start();
    state = executeCommand(cyberRangeSpec, state, "ssh dbadmin@db01 S3cur3DbPass!").state;

    const flag = executeCommand(cyberRangeSpec, state, "cat flag.txt");
    expect(flag.output).toBe("ICOREPEN{lateral_movement_via_leaked_db_credentials}");

    expect(executeCommand(cyberRangeSpec, state, "hostname").output).toBe("db01");
    expect(executeCommand(cyberRangeSpec, state, "whoami").output).toBe("dbadmin");
    expect(executeCommand(cyberRangeSpec, state, "pwd").output).toBe("/home/dbadmin");
  });

  it("db01 cannot pivot anywhere further -- its own reachable_hosts is empty", () => {
    const state = executeCommand(cyberRangeSpec, start(), "ssh dbadmin@db01 S3cur3DbPass!").state;
    const { output } = executeCommand(cyberRangeSpec, state, "ssh root@web01 anything");
    expect(output).toBe("ssh: connect to host web01 port 22: No route to host");
  });
});

describe("exit / logout: returning to the previous host", () => {
  it("refuses to exit the origin session", () => {
    const { output, state } = executeCommand(cyberRangeSpec, start(), "exit");
    expect(output).toBe("exit: cannot exit the origin session");
    expect(state.host).toBe("web01");
  });

  it("restores the exact suspended session (host/user/cwd) on the origin host after pivoting and exiting", () => {
    let state = start();
    state = executeCommand(cyberRangeSpec, state, "cd /home/user").state;
    state = executeCommand(cyberRangeSpec, state, "ssh dbadmin@db01 S3cur3DbPass!").state;
    expect(state.host).toBe("db01");

    const afterExit = executeCommand(cyberRangeSpec, state, "exit");
    expect(afterExit.output).toBe("Connection to db01 closed.");
    expect(afterExit.state.host).toBe("web01");
    expect(afterExit.state.user).toBe("user");
    expect(afterExit.state.cwd).toBe("/home/user");
  });

  it("logout is an alias for exit", () => {
    const state = executeCommand(cyberRangeSpec, start(), "ssh dbadmin@db01 S3cur3DbPass!").state;
    const { output } = executeCommand(cyberRangeSpec, state, "logout");
    expect(output).toBe("Connection to db01 closed.");
  });

  it("preserves discovered files across a pivot and exit (used for lab progress signals)", () => {
    let state = start();
    state = executeCommand(cyberRangeSpec, state, "cat db-backup.conf").state;
    expect(state.discovered).toContain("/home/user/db-backup.conf");

    state = executeCommand(cyberRangeSpec, state, "ssh dbadmin@db01 S3cur3DbPass!").state;
    state = executeCommand(cyberRangeSpec, state, "cat flag.txt").state;
    expect(state.discovered).toContain("/home/dbadmin/flag.txt");

    state = executeCommand(cyberRangeSpec, state, "exit").state;
    expect(state.discovered).toContain("/home/user/db-backup.conf");
    expect(state.discovered).toContain("/home/dbadmin/flag.txt");
  });
});

describe("ssh: usage error", () => {
  it("reports usage when the target isn't a valid user@host", () => {
    const { output } = executeCommand(cyberRangeSpec, start(), "ssh db01");
    expect(output).toBe("usage: ssh <user>@<hostname> <password>");
  });
});
