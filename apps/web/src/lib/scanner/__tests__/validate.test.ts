import { describe, expect, it } from "vitest";
import { validateScanFiles, ScanValidationError } from "../validate";

describe("validateScanFiles", () => {
  it("rejects an empty file list", () => {
    expect(() => validateScanFiles([])).toThrow(ScanValidationError);
  });

  it("rejects more than 20 files", () => {
    const files = Array.from({ length: 21 }, (_, i) => ({ filename: `f${i}.js`, content: "const x = 1;" }));
    expect(() => validateScanFiles(files)).toThrow(ScanValidationError);
  });

  it("rejects a file over the size limit", () => {
    const files = [{ filename: "big.js", content: "x".repeat(300_001) }];
    expect(() => validateScanFiles(files)).toThrow(ScanValidationError);
  });

  it("accepts a reasonable set of files", () => {
    const files = [
      { filename: "a.js", content: "const x = 1;" },
      { filename: "b.py", content: "x = 1" },
    ];
    expect(() => validateScanFiles(files)).not.toThrow();
  });
});
