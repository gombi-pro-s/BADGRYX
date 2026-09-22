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

export const environmentSpecSchema = z.object({
  hostname: z.string().min(1).max(64),
  initial_cwd: z.string().min(1).max(500),
  initial_user: z.string().min(1).max(64).default("user"),
  users: z.array(z.string()).default(["user", "root"]),
  filesystem: z.record(z.string(), filesystemEntrySchema),
  sudo_rules: z.array(sudoRuleSchema).default([]),
});

export type FilesystemFile = z.infer<typeof filesystemFileSchema>;
export type FilesystemDir = z.infer<typeof filesystemDirSchema>;
export type FilesystemEntry = z.infer<typeof filesystemEntrySchema>;
export type SudoRule = z.infer<typeof sudoRuleSchema>;
export type EnvironmentSpec = z.infer<typeof environmentSpecSchema>;

export interface TerminalState {
  cwd: string;
  user: string;
  discovered: string[];
}

export function initialTerminalState(spec: EnvironmentSpec): TerminalState {
  return { cwd: spec.initial_cwd, user: spec.initial_user, discovered: [] };
}
