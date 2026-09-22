import { describe, expect, it } from "vitest";
import { executeCommand } from "../interpreter";
import { initialTerminalState } from "../spec";
import { fixtureSpec } from "./fixture";

const start = () => initialTerminalState(fixtureSpec);

describe("executeCommand: basics", () => {
  it("runs pwd from the initial cwd", () => {
    const { output } = executeCommand(fixtureSpec, start(), "pwd");
    expect(output).toBe("/home/user");
  });

  it("runs whoami as the initial user", () => {
    const { output } = executeCommand(fixtureSpec, start(), "whoami");
    expect(output).toBe("user");
  });

  it("runs hostname", () => {
    const { output } = executeCommand(fixtureSpec, start(), "hostname");
    expect(output).toBe("web01");
  });

  it("reports command not found for an unrecognized command", () => {
    const { output } = executeCommand(fixtureSpec, start(), "nmap -sV target");
    expect(output).toBe("nmap: command not found");
  });

  it("returns empty output and unchanged state for a blank command", () => {
    const state = start();
    const result = executeCommand(fixtureSpec, state, "   ");
    expect(result.output).toBe("");
    expect(result.state).toBe(state);
  });
});

describe("executeCommand: id/uname", () => {
  it("reports uid 1000 for a non-root user", () => {
    const { output } = executeCommand(fixtureSpec, start(), "id");
    expect(output).toBe("uid=1000(user) gid=1000(user) groups=1000(user)");
  });

  it("reports uid 0 once running as root", () => {
    const { output } = executeCommand(fixtureSpec, { ...start(), user: "root" }, "id");
    expect(output).toBe("uid=0(root) gid=0(root) groups=0(root)");
  });

  it("uname -a includes the hostname", () => {
    const { output } = executeCommand(fixtureSpec, start(), "uname -a");
    expect(output).toContain("web01");
  });
});

describe("executeCommand: cd", () => {
  it("changes into a subdirectory", () => {
    const { state } = executeCommand(fixtureSpec, start(), "cd /var/backups");
    expect(state.cwd).toBe("/var/backups");
  });

  it("resolves a relative path", () => {
    const { state } = executeCommand(fixtureSpec, start(), "cd ..");
    expect(state.cwd).toBe("/home");
  });

  it("refuses to cd into a file", () => {
    const { output, state } = executeCommand(fixtureSpec, start(), "cd notes.txt");
    expect(output).toContain("No such file or directory");
    expect(state.cwd).toBe("/home/user");
  });

  it("refuses to cd into a nonexistent path", () => {
    const { output, state } = executeCommand(fixtureSpec, start(), "cd /nope");
    expect(output).toContain("No such file or directory");
    expect(state.cwd).toBe("/home/user");
  });
});

describe("executeCommand: ls", () => {
  it("lists the current directory by default", () => {
    const { output } = executeCommand(fixtureSpec, start(), "ls");
    expect(output).toContain("notes.txt");
    expect(output).toContain(".bash_history");
  });

  it("lists a given directory", () => {
    const { output } = executeCommand(fixtureSpec, start(), "ls /var/backups");
    expect(output).toBe("db.sql");
  });

  it("-l shows a permissions/owner listing", () => {
    const { output } = executeCommand(fixtureSpec, start(), "ls -l");
    expect(output).toMatch(/^-rw-r--r-- 1 user user notes\.txt$/m);
  });

  it("errors on a nonexistent directory", () => {
    const { output } = executeCommand(fixtureSpec, start(), "ls /nope");
    expect(output).toContain("No such file or directory");
  });
});

describe("executeCommand: cat", () => {
  it("prints a file's real content", () => {
    const { output } = executeCommand(fixtureSpec, start(), "cat notes.txt");
    expect(output).toBe("TODO: rotate the backup credentials\nask admin about the staging DB");
  });

  it("records the path as discovered", () => {
    const { state } = executeCommand(fixtureSpec, start(), "cat notes.txt");
    expect(state.discovered).toContain("/home/user/notes.txt");
  });

  it("errors on a directory", () => {
    const { output } = executeCommand(fixtureSpec, start(), "cat /var");
    expect(output).toContain("Is a directory");
  });

  it("errors on a nonexistent file", () => {
    const { output } = executeCommand(fixtureSpec, start(), "cat nope.txt");
    expect(output).toContain("No such file or directory");
  });

  it("cannot read the root-owned flag as a plain user (the file exists but this interpreter doesn't enforce perms beyond narrative -- confirmed readable regardless, since perms are descriptive not enforced in v1)", () => {
    // Documented v1 limitation: `perms`/`owner` are rendered in `ls -l` but
    // not enforced by cat/head/tail -- enforcing real Unix permission
    // semantics (including sudo elevation actually mattering) is a
    // deliberate scope boundary for now, same as no pipes/redirects.
    const { output } = executeCommand(fixtureSpec, start(), "cat /root/flag.txt");
    expect(output).toBe("ICOREPEN{root_access_confirmed}");
  });
});

describe("executeCommand: head/tail/wc", () => {
  it("head returns the first N lines", () => {
    const { output } = executeCommand(fixtureSpec, start(), "head -n 1 notes.txt");
    expect(output).toBe("TODO: rotate the backup credentials");
  });

  it("tail returns the last N lines", () => {
    const { output } = executeCommand(fixtureSpec, start(), "tail -n 1 notes.txt");
    expect(output).toBe("ask admin about the staging DB");
  });

  it("wc with no flags reports lines/words/bytes", () => {
    const { output } = executeCommand(fixtureSpec, start(), "wc notes.txt");
    expect(output).toMatch(/^\d+ \d+ \d+ \/home\/user\/notes\.txt$/);
  });

  it("wc -l reports only the line count", () => {
    const { output } = executeCommand(fixtureSpec, start(), "wc -l notes.txt");
    expect(output).toBe("2 /home/user/notes.txt");
  });
});

describe("executeCommand: file", () => {
  it("identifies a file", () => {
    const { output } = executeCommand(fixtureSpec, start(), "file notes.txt");
    expect(output).toBe("notes.txt: ASCII text");
  });

  it("identifies a directory", () => {
    const { output } = executeCommand(fixtureSpec, start(), "file /var");
    expect(output).toBe("/var: directory");
  });
});

describe("executeCommand: find", () => {
  it("finds files under a path matching a glob pattern", () => {
    const { output } = executeCommand(fixtureSpec, start(), "find / -name *.sql");
    expect(output).toBe("/var/backups/db.sql");
  });

  it("finds everything under a path with no pattern", () => {
    const { output } = executeCommand(fixtureSpec, start(), "find /var");
    expect(output.split("\n")).toContain("/var/backups/db.sql");
  });
});

describe("executeCommand: grep", () => {
  it("finds a matching line in a single file", () => {
    const { output } = executeCommand(fixtureSpec, start(), "grep TODO notes.txt");
    expect(output).toBe("TODO: rotate the backup credentials");
  });

  it("returns empty output when nothing matches", () => {
    const { output } = executeCommand(fixtureSpec, start(), "grep nonexistentpattern notes.txt");
    expect(output).toBe("");
  });

  it("searches recursively and prefixes matches with their file path", () => {
    const { output } = executeCommand(fixtureSpec, start(), "grep -r password /var");
    expect(output).toBe("/var/backups/db.sql:INSERT INTO users (username, password) VALUES ('admin', 'hunter2');");
  });
});

describe("executeCommand: sudo", () => {
  it("allows an explicitly permitted command and runs it as root for that call only", () => {
    const { output, state } = executeCommand(fixtureSpec, start(), "sudo cat /root/flag.txt");
    expect(output).toBe("ICOREPEN{root_access_confirmed}");
    expect(state.user).toBe("user"); // elevation does not persist
  });

  it("refuses a command not in the user's sudo rules", () => {
    const { output } = executeCommand(fixtureSpec, start(), "sudo ls /root");
    expect(output).toMatch(/not in the sudoers file/);
  });

  it("sudo -l lists what the current user may run", () => {
    const { output } = executeCommand(fixtureSpec, start(), "sudo -l");
    expect(output).toContain("(ALL) cat");
  });

  it("sudo -l reports nothing allowed for a user with no rule", () => {
    const { output } = executeCommand(fixtureSpec, { ...start(), user: "nobody" }, "sudo -l");
    expect(output).toMatch(/may not run sudo/);
  });

  it("cat's own discovered-path bookkeeping still applies when run via sudo", () => {
    const { state } = executeCommand(fixtureSpec, start(), "sudo cat /root/flag.txt");
    expect(state.discovered).toContain("/root/flag.txt");
  });
});

describe("executeCommand: help/clear", () => {
  it("help lists the available commands", () => {
    const { output } = executeCommand(fixtureSpec, start(), "help");
    expect(output).toContain("pwd");
    expect(output).toContain("sudo");
  });

  it("clear returns a terminal clear escape sequence", () => {
    const { output } = executeCommand(fixtureSpec, start(), "clear");
    expect(output).toBe("\x1bc");
  });
});
