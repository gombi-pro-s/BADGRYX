import type { EnvironmentSpec, TerminalState } from "./spec";
import { canReadFile, getEntry, isDirectory, isFile, listChildren, resolvePath } from "./path";
import { tokenize } from "./tokenize";

export interface CommandResult {
  output: string;
  state: TerminalState;
}

/**
 * A real, deterministic interpreter for a bounded subset of Unix-like
 * commands, run entirely against the JSON filesystem tree in an
 * EnvironmentSpec -- pure function, no I/O, so it's fully unit-testable
 * without a database or a real shell (see __tests__).
 *
 * Deliberately NOT a shell: no pipes, redirects, `&&`/`;` chaining,
 * variable expansion, or subshells. Each call runs exactly one command.
 * This is an honest scope boundary (like the scanner's rule engine not
 * being a real parser) -- documented here rather than silently missing.
 */
export function executeCommand(spec: EnvironmentSpec, state: TerminalState, commandLine: string): CommandResult {
  const trimmed = commandLine.trim();
  if (trimmed.length === 0) return { output: "", state };

  const [cmd, ...args] = tokenize(trimmed);
  const handler = COMMANDS[cmd];
  if (!handler) {
    return { output: `${cmd}: command not found`, state };
  }
  return handler(args, spec, state);
}

function resolveUid(user: string): number {
  return user === "root" ? 0 : 1000;
}

function readTarget(spec: EnvironmentSpec, state: TerminalState, args: string[]): { path: string; content: string } | { error: string } {
  const nFlagIdx = args.indexOf("-n");
  const target = args.find((a, i) => !a.startsWith("-") && !(nFlagIdx >= 0 && i === nFlagIdx + 1));
  if (!target) return { error: "missing file operand" };
  const path = resolvePath(state.cwd, target);
  const entry = getEntry(spec, path);
  if (!entry) {
    if (isDirectory(spec, path)) return { error: `${target}: Is a directory` };
    return { error: `${target}: No such file or directory` };
  }
  if (entry.type !== "file") return { error: `${target}: Is a directory` };
  if (!canReadFile(entry, state.user)) return { error: `${target}: Permission denied` };
  return { path, content: entry.content };
}

const COMMANDS: Record<string, (args: string[], spec: EnvironmentSpec, state: TerminalState) => CommandResult> = {
  help: (_args, _spec, state) => ({
    output: [
      "Available commands:",
      "  pwd, cd, ls, cat, echo, head, tail, wc, file, find, grep,",
      "  whoami, id, hostname, uname, sudo, clear, help",
      "No pipes, redirects, or command chaining -- one command at a time.",
      "Use the up/down arrows to recall previous commands.",
    ].join("\n"),
    state,
  }),

  pwd: (_args, _spec, state) => ({ output: state.cwd, state }),

  whoami: (_args, _spec, state) => ({ output: state.user, state }),

  hostname: (_args, spec, state) => ({ output: spec.hostname, state }),

  id: (_args, _spec, state) => {
    const uid = resolveUid(state.user);
    return { output: `uid=${uid}(${state.user}) gid=${uid}(${state.user}) groups=${uid}(${state.user})`, state };
  },

  uname: (args, spec, state) => {
    if (args.includes("-a")) {
      return { output: `Linux ${spec.hostname} 5.15.0-generic #1 SMP x86_64 GNU/Linux`, state };
    }
    return { output: "Linux", state };
  },

  echo: (args, _spec, state) => ({ output: args.join(" "), state }),

  cd: (args, spec, state) => {
    const target = args[0];
    const newCwd = resolvePath(state.cwd, target ?? spec.initial_cwd);
    if (!isDirectory(spec, newCwd)) {
      return { output: `cd: ${target}: No such file or directory`, state };
    }
    return { output: "", state: { ...state, cwd: newCwd } };
  },

  ls: (args, spec, state) => {
    const long = args.includes("-l") || args.includes("-la") || args.includes("-al");
    const targetArg = args.find((a) => !a.startsWith("-"));
    const path = resolvePath(state.cwd, targetArg ?? ".");

    if (isFile(spec, path)) {
      return { output: path.split("/").pop() ?? path, state };
    }
    if (!isDirectory(spec, path)) {
      return { output: `ls: cannot access '${targetArg ?? "."}': No such file or directory`, state };
    }

    const children = listChildren(spec, path);
    if (children.length === 0) return { output: "", state };

    if (!long) {
      return { output: children.map((c) => c.name).join("  "), state };
    }
    const lines = children.map((c) => {
      const entry = getEntry(spec, c.path);
      const perms = entry?.perms ?? (c.type === "dir" ? "rwxr-xr-x" : "rw-r--r--");
      const owner = entry?.owner ?? "user";
      const typeChar = c.type === "dir" ? "d" : "-";
      return `${typeChar}${perms} 1 ${owner} ${owner} ${c.name}`;
    });
    return { output: lines.join("\n"), state };
  },

  cat: (args, spec, state) => {
    if (args.length === 0) return { output: "cat: missing file operand", state };
    const outputs: string[] = [];
    let newDiscovered = state.discovered;
    for (const target of args) {
      const path = resolvePath(state.cwd, target);
      const entry = getEntry(spec, path);
      if (!entry) {
        outputs.push(isDirectory(spec, path) ? `cat: ${target}: Is a directory` : `cat: ${target}: No such file or directory`);
        continue;
      }
      if (entry.type !== "file") {
        outputs.push(`cat: ${target}: Is a directory`);
        continue;
      }
      if (!canReadFile(entry, state.user)) {
        outputs.push(`cat: ${target}: Permission denied`);
        continue;
      }
      outputs.push(entry.content);
      if (!newDiscovered.includes(path)) newDiscovered = [...newDiscovered, path];
    }
    return { output: outputs.join("\n"), state: { ...state, discovered: newDiscovered } };
  },

  head: (args, spec, state) => {
    const nFlagIdx = args.indexOf("-n");
    const n = nFlagIdx >= 0 ? parseInt(args[nFlagIdx + 1] ?? "10", 10) : 10;
    const result = readTarget(spec, state, args);
    if ("error" in result) return { output: `head: ${result.error}`, state };
    return { output: result.content.split("\n").slice(0, n).join("\n"), state };
  },

  tail: (args, spec, state) => {
    const nFlagIdx = args.indexOf("-n");
    const n = nFlagIdx >= 0 ? parseInt(args[nFlagIdx + 1] ?? "10", 10) : 10;
    const result = readTarget(spec, state, args);
    if ("error" in result) return { output: `tail: ${result.error}`, state };
    const lines = result.content.split("\n");
    return { output: lines.slice(Math.max(0, lines.length - n)).join("\n"), state };
  },

  wc: (args, spec, state) => {
    const result = readTarget(spec, state, args);
    if ("error" in result) return { output: `wc: ${result.error}`, state };
    const lines = result.content.split("\n").length;
    const words = result.content.split(/\s+/).filter(Boolean).length;
    const bytes = result.content.length;
    if (args.includes("-l")) return { output: `${lines} ${result.path}`, state };
    if (args.includes("-w")) return { output: `${words} ${result.path}`, state };
    if (args.includes("-c")) return { output: `${bytes} ${result.path}`, state };
    return { output: `${lines} ${words} ${bytes} ${result.path}`, state };
  },

  file: (args, spec, state) => {
    const target = args[0];
    if (!target) return { output: "file: missing operand", state };
    const path = resolvePath(state.cwd, target);
    const entry = getEntry(spec, path);
    if (entry?.type === "dir" || (!entry && isDirectory(spec, path))) return { output: `${target}: directory`, state };
    if (entry?.type === "file") return { output: `${target}: ASCII text`, state };
    return { output: `${target}: cannot open (No such file or directory)`, state };
  },

  find: (args, spec, state) => {
    const nameFlagIdx = args.indexOf("-name");
    const pattern = nameFlagIdx >= 0 ? args[nameFlagIdx + 1] : undefined;
    const startArg = args.find((a) => !a.startsWith("-") && a !== pattern);
    const startPath = resolvePath(state.cwd, startArg ?? ".");
    const regex = pattern ? globToRegExp(pattern) : null;

    const matches = Object.keys(spec.filesystem)
      .filter((p) => p === startPath || p.startsWith(startPath === "/" ? "/" : `${startPath}/`))
      .filter((p) => !regex || regex.test(p.split("/").pop() ?? ""))
      .sort();

    return { output: matches.length > 0 ? matches.join("\n") : "", state };
  },

  grep: (args, spec, state) => {
    const recursive = args.includes("-r") || args.includes("-R");
    const positional = args.filter((a) => !a.startsWith("-"));
    const pattern = positional[0];
    const target = positional[1];
    if (!pattern || !target) return { output: "grep: missing pattern or file", state };

    const startPath = resolvePath(state.cwd, target);
    let matcher: RegExp;
    try {
      matcher = new RegExp(pattern);
    } catch {
      return { output: `grep: invalid pattern: ${pattern}`, state };
    }

    if (!recursive) {
      const entry = getEntry(spec, startPath);
      if (!entry || entry.type !== "file") {
        return { output: `grep: ${target}: No such file or directory`, state };
      }
      if (!canReadFile(entry, state.user)) {
        return { output: `grep: ${target}: Permission denied`, state };
      }
    }

    const filesToSearch: string[] = recursive
      ? Object.keys(spec.filesystem).filter((p) => {
          const entry = getEntry(spec, p);
          return (
            entry?.type === "file" &&
            canReadFile(entry, state.user) &&
            (p === startPath || p.startsWith(startPath === "/" ? "/" : `${startPath}/`))
          );
        })
      : [startPath];

    const lines: string[] = [];
    for (const path of filesToSearch) {
      const entry = getEntry(spec, path);
      if (entry?.type !== "file") continue;
      for (const line of entry.content.split("\n")) {
        if (matcher.test(line)) {
          lines.push(recursive || filesToSearch.length > 1 ? `${path}:${line}` : line);
        }
      }
    }
    return { output: lines.join("\n"), state };
  },

  sudo: (args, spec, state) => {
    if (args[0] === "-l") {
      const rule = spec.sudo_rules.find((r) => r.user === state.user);
      if (!rule) return { output: `Sorry, user ${state.user} may not run sudo on ${spec.hostname}.`, state };
      const allowed = rule.allowed === "all" ? "(ALL) ALL" : rule.allowed.map((c) => `(ALL) ${c}`).join("\n");
      return { output: `User ${state.user} may run the following commands on ${spec.hostname}:\n${allowed}`, state };
    }

    if (args.length === 0) return { output: "sudo: a command is required", state };

    const rule = spec.sudo_rules.find((r) => r.user === state.user);
    const commandName = args[0];
    const isAllowed = rule && (rule.allowed === "all" || rule.allowed.includes(commandName));
    if (!isAllowed) {
      return { output: `${state.user} is not in the sudoers file. This incident will be reported.`, state };
    }

    const asRoot: TerminalState = { ...state, user: "root" };
    const result = executeCommand(spec, asRoot, args.join(" "));
    // Running as root for this one command must not persist -- only its
    // side effects on cwd/discovered carry forward, not the elevated user.
    return { output: result.output, state: { ...result.state, user: state.user } };
  },

  clear: (_args, _spec, state) => ({ output: "\x1bc", state }),
};

function globToRegExp(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".");
  return new RegExp(`^${escaped}$`);
}
