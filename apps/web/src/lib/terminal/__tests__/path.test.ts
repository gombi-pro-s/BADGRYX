import { describe, expect, it } from "vitest";
import { getEntry, isDirectory, isFile, listChildren, resolvePath } from "../path";
import { fixtureSpec } from "./fixture";

describe("resolvePath", () => {
  it("resolves a relative path against cwd", () => {
    expect(resolvePath("/home/user", "notes.txt")).toBe("/home/user/notes.txt");
  });
  it("passes through an absolute path unchanged (structurally)", () => {
    expect(resolvePath("/home/user", "/var/backups")).toBe("/var/backups");
  });
  it("collapses .. segments", () => {
    expect(resolvePath("/home/user", "..")).toBe("/home");
  });
  it("collapses . segments (no-op)", () => {
    expect(resolvePath("/home/user", ".")).toBe("/home/user");
  });
  it("does not go above root when .. is used at the top", () => {
    expect(resolvePath("/", "..")).toBe("/");
  });
  it("resolves a compound relative path", () => {
    expect(resolvePath("/home/user", "../../var/backups")).toBe("/var/backups");
  });
});

describe("filesystem introspection", () => {
  it("getEntry returns the declared entry for an explicit path", () => {
    expect(getEntry(fixtureSpec, "/home/user/notes.txt")).toEqual(fixtureSpec.filesystem["/home/user/notes.txt"]);
  });
  it("getEntry returns null for an undeclared path", () => {
    expect(getEntry(fixtureSpec, "/nope")).toBeNull();
  });

  it("isDirectory is true for an explicitly declared dir", () => {
    expect(isDirectory(fixtureSpec, "/home/user")).toBe(true);
  });
  it("isDirectory is true for an implicit dir inferred from a descendant file", () => {
    // /var and /var/backups are never declared explicitly, only /var/backups/db.sql is.
    expect(isDirectory(fixtureSpec, "/var")).toBe(true);
    expect(isDirectory(fixtureSpec, "/var/backups")).toBe(true);
  });
  it("isDirectory is false for a file path", () => {
    expect(isDirectory(fixtureSpec, "/home/user/notes.txt")).toBe(false);
  });
  it("isDirectory is true for the root", () => {
    expect(isDirectory(fixtureSpec, "/")).toBe(true);
  });

  it("isFile is true only for declared files", () => {
    expect(isFile(fixtureSpec, "/home/user/notes.txt")).toBe(true);
    expect(isFile(fixtureSpec, "/home/user")).toBe(false);
    expect(isFile(fixtureSpec, "/var")).toBe(false);
  });
});

describe("listChildren", () => {
  it("lists both files and the implicit .bash_history dotfile in a declared directory", () => {
    const children = listChildren(fixtureSpec, "/home/user").map((c) => c.name);
    expect(children).toContain("notes.txt");
    expect(children).toContain(".bash_history");
  });

  it("lists an implicit directory's single descendant", () => {
    const children = listChildren(fixtureSpec, "/var/backups");
    expect(children).toEqual([{ name: "db.sql", path: "/var/backups/db.sql", type: "file" }]);
  });

  it("lists an intermediate implicit directory as a single child, not its full descendants", () => {
    const children = listChildren(fixtureSpec, "/var");
    expect(children).toEqual([{ name: "backups", path: "/var/backups", type: "dir" }]);
  });

  it("lists a directory's single file", () => {
    expect(listChildren(fixtureSpec, "/root")).toEqual([{ name: "flag.txt", path: "/root/flag.txt", type: "file" }]);
  });

  it("returns an empty list for an explicitly declared, genuinely empty directory", () => {
    expect(listChildren(fixtureSpec, "/tmp")).toEqual([]);
  });
});
