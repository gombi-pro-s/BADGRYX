import type { EnvironmentSpec, FilesystemEntry } from "./spec";

/** Joins/resolves `input` against `cwd` (POSIX-style: absolute inputs replace cwd entirely, `.`/`..` are collapsed). Always returns an absolute path with no trailing slash (except root, which is exactly "/"). */
export function resolvePath(cwd: string, input: string): string {
  const base = input.startsWith("/") ? input : `${cwd === "/" ? "" : cwd}/${input}`;
  const segments = base.split("/").filter((s) => s.length > 0 && s !== ".");
  const resolved: string[] = [];
  for (const segment of segments) {
    if (segment === "..") {
      resolved.pop();
    } else {
      resolved.push(segment);
    }
  }
  return "/" + resolved.join("/");
}

/** The direct entry for `path`, if it was declared explicitly in the spec. */
export function getEntry(spec: EnvironmentSpec, path: string): FilesystemEntry | null {
  return spec.filesystem[path] ?? null;
}

/**
 * True if `path` behaves as a directory: either explicitly declared
 * `type: "dir"`, is the filesystem root, or some other entry's path has it
 * as a prefix (an implicit directory -- authors don't have to declare every
 * intermediate directory just to place a file deep in a tree).
 */
export function isDirectory(spec: EnvironmentSpec, path: string): boolean {
  if (path === "/") return true;
  const entry = getEntry(spec, path);
  if (entry?.type === "dir") return true;
  if (entry?.type === "file") return false;
  const prefix = path === "/" ? "/" : `${path}/`;
  return Object.keys(spec.filesystem).some((p) => p.startsWith(prefix));
}

export function isFile(spec: EnvironmentSpec, path: string): boolean {
  return getEntry(spec, path)?.type === "file";
}

/**
 * Real (if simplified) Unix read-permission check: root can read anything;
 * the declared owner is checked against the owner triad of `perms`
 * ("rwxr-xr-x" -- positions 0-2), everyone else against the "other" triad
 * (positions 6-8). No group modeling in v1. Defaults to world-readable
 * ("rw-r--r--") when a file declares no perms, matching a typical default
 * umask. This is what actually makes a "misconfigured sudo" / privilege
 * escalation lab meaningful -- without it, `cat` would happily return any
 * file's content regardless of ownership, and sudo would never matter.
 */
export function canReadFile(entry: FilesystemEntry, user: string): boolean {
  if (user === "root") return true;
  const perms = entry.perms ?? "rw-r--r--";
  if (entry.owner && entry.owner === user) {
    return perms[0] === "r";
  }
  return perms[6] === "r";
}

export interface DirectoryChild {
  name: string;
  path: string;
  type: "file" | "dir";
}

/** Immediate children of a directory path, sorted, deduplicated (a directory can be "known" both explicitly and by having descendants). */
export function listChildren(spec: EnvironmentSpec, dirPath: string): DirectoryChild[] {
  const prefix = dirPath === "/" ? "/" : `${dirPath}/`;
  const children = new Map<string, DirectoryChild>();

  for (const path of Object.keys(spec.filesystem)) {
    if (path === dirPath || !path.startsWith(prefix)) continue;
    const remainder = path.slice(prefix.length);
    const firstSegment = remainder.split("/")[0];
    const childPath = `${prefix}${firstSegment}`;
    const isDirectChild = remainder === firstSegment;
    children.set(firstSegment, {
      name: firstSegment,
      path: childPath,
      type: isDirectChild ? spec.filesystem[childPath]?.type ?? "file" : "dir",
    });
  }

  return [...children.values()].sort((a, b) => a.name.localeCompare(b.name));
}
