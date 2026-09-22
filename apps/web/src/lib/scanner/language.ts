const EXTENSION_LANGUAGE: Record<string, string> = {
  js: "javascript",
  jsx: "javascript",
  mjs: "javascript",
  cjs: "javascript",
  ts: "typescript",
  tsx: "typescript",
  py: "python",
  rb: "ruby",
  php: "php",
  java: "java",
  go: "go",
  cs: "csharp",
  sql: "sql",
  sh: "shell",
  bash: "shell",
  yml: "yaml",
  yaml: "yaml",
  json: "json",
  html: "html",
  htm: "html",
  vue: "vue",
};

/** Best-effort language guess from a filename extension. Null if unrecognized -- rules that need a language skip the file rather than guessing. */
export function detectLanguage(filename: string): string | null {
  const ext = filename.split(".").pop()?.toLowerCase();
  if (!ext) return null;
  return EXTENSION_LANGUAGE[ext] ?? null;
}
