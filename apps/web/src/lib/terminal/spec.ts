import { z } from "zod";

/**
 * The shape of a lab_environments.spec row -- an authored virtual
 * filesystem, deliberately simple (a flat map of absolute path -> entry,
 * directories inferred from path prefixes where not declared explicitly)
 * so it's easy to author by hand in the admin UI (see lib/terminal's other
 * files for the interpreter that runs against this).
 */

export const filesystemFileSchema = z.object({
  type: z.literal("file"),
  content: z.string().max(20000),
  owner: z.string().optional(),
  perms: z.string().optional(),
});

export const filesystemDirSchema = z.object({
  type: z.literal("dir"),
  owner: z.string().optional(),
  perms: z.string().optional(),
});

export const filesystemEntrySchema = z.discriminatedUnion("type", [filesystemFileSchema, filesystemDirSchema]);

export const sudoRuleSchema = z.object({
  user: z.string(),
  allowed: z.union([z.literal("all"), z.array(z.string())]),
});

export const credentialSchema = z.object({
  user: z.string(),
  password: z.string(),
});

/**
 * A second (or third, ...) host in a "Cyber Range" multi-host environment,
 * reached from another host via `ssh`. Deliberately mirrors the primary
 * host's own fields (filesystem/users/sudo_rules) rather than nesting a
 * full EnvironmentSpec, since a remote host is never itself an entry point
 * -- there's no `initial_user` to log in as automatically; `ssh` always
 * requires a matching credential.
 */
export const remoteHostSchema = z.object({
  hostname: z.string().min(1).max(64),
  initial_cwd: z.string().min(1).max(500),
  users: z.array(z.string()).default(["user", "root"]),
  filesystem: z.record(z.string(), filesystemEntrySchema),
  sudo_rules: z.array(sudoRuleSchema).default([]),
  credentials: z.array(credentialSchema).default([]),
  reachable_hosts: z.array(z.string()).default([]),
});

export const environmentSpecSchema = z.object({
  hostname: z.string().min(1).max(64),
  initial_cwd: z.string().min(1).max(500),
  initial_user: z.string().min(1).max(64).default("user"),
  users: z.array(z.string()).default(["user", "root"]),
  filesystem: z.record(z.string(), filesystemEntrySchema),
  sudo_rules: z.array(sudoRuleSchema).default([]),
  // Cyber Range extension (additive, all defaulted -- every pre-existing
  // single-host spec keeps working unchanged): hostnames reachable via
  // `ssh` directly from this, the entry host, and the additional hosts
  // themselves, keyed by hostname.
  reachable_hosts: z.array(z.string()).default([]),
  hosts: z.record(z.string(), remoteHostSchema).default({}),
});

export type FilesystemFile = z.infer<typeof filesystemFileSchema>;
export type FilesystemDir = z.infer<typeof filesystemDirSchema>;
export type FilesystemEntry = z.infer<typeof filesystemEntrySchema>;
export type SudoRule = z.infer<typeof sudoRuleSchema>;
export type Credential = z.infer<typeof credentialSchema>;
export type RemoteHost = z.infer<typeof remoteHostSchema>;
export type EnvironmentSpec = z.infer<typeof environmentSpecSchema>;

/** A normalized view of whichever host is "current" -- the entry host's own top-level fields, or one of `hosts`, behind one shape so command handlers never need to branch on which. */
export interface ResolvedHost {
  hostname: string;
  initial_cwd: string;
  users: string[];
  filesystem: Record<string, FilesystemEntry>;
  sudo_rules: SudoRule[];
  credentials: Credential[];
  reachable_hosts: string[];
}

/** Resolves `hostname` against the entry host or `spec.hosts`. Returns null for an unknown hostname (never reachable via `ssh` in that case). */
export function resolveHost(spec: EnvironmentSpec, hostname: string): ResolvedHost | null {
  if (hostname === spec.hostname) {
    return {
      hostname: spec.hostname,
      initial_cwd: spec.initial_cwd,
      users: spec.users,
      filesystem: spec.filesystem,
      sudo_rules: spec.sudo_rules,
      credentials: [],
      reachable_hosts: spec.reachable_hosts,
    };
  }
  return spec.hosts[hostname] ?? null;
}

export interface HostSession {
  host: string;
  user: string;
  cwd: string;
}

export interface TerminalState {
  cwd: string;
  user: string;
  discovered: string[];
  host: string;
  /** Sessions to return to on `exit`/`logout` -- pushed by `ssh`, popped on exit. Empty at the origin host. */
  sessionStack: HostSession[];
}

export function initialTerminalState(spec: EnvironmentSpec): TerminalState {
  return { cwd: spec.initial_cwd, user: spec.initial_user, discovered: [], host: spec.hostname, sessionStack: [] };
}
