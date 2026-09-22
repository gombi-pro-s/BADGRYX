const MAX_EVIDENCE_LENGTH = 300;

/** 1-indexed line number containing byte offset `index` into `content`. */
export function lineNumberAt(content: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index && i < content.length; i++) {
    if (content[i] === "\n") line++;
  }
  return line;
}

/** The full source line a given 1-indexed line number refers to, trimmed and length-capped for storage as evidence. */
export function getLineText(content: string, lineNumber: number): string {
  const lines = content.split("\n");
  const text = lines[lineNumber - 1] ?? "";
  const trimmed = text.trim();
  return trimmed.length > MAX_EVIDENCE_LENGTH ? trimmed.slice(0, MAX_EVIDENCE_LENGTH) + "…" : trimmed;
}

export type PatternMatch = { match: RegExpExecArray; line: number };

/**
 * Runs `pattern` against the whole file content (so patterns can span line
 * boundaries, e.g. multi-line PEM blocks) and returns every match with its
 * starting line number. `pattern` is always run with the `g` flag,
 * regardless of what was passed in, so every rule gets every match rather
 * than just the first.
 */
export function findAllMatches(content: string, pattern: RegExp): PatternMatch[] {
  const flags = pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g";
  const re = new RegExp(pattern.source, flags);
  const results: PatternMatch[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(content)) !== null) {
    results.push({ match: m, line: lineNumberAt(content, m.index) });
    if (m[0].length === 0) re.lastIndex++;
  }
  return results;
}

/** Line number of the last character of a match, for multi-line matches. */
export function endLineNumber(content: string, match: RegExpExecArray): number {
  return lineNumberAt(content, match.index + match[0].length);
}

/**
 * Given the index of an opening bracket/paren, returns the text between it
 * and its matching closer (not including the brackets themselves), tracking
 * nesting depth. Used to pull out call arguments / assignment RHS for
 * sinks like `innerHTML = ...` or `exec(...)` without a full parser.
 */
export function extractBalanced(content: string, openIndex: number, open = "(", close = ")"): string {
  let depth = 0;
  for (let i = openIndex; i < content.length; i++) {
    if (content[i] === open) depth++;
    else if (content[i] === close) {
      depth--;
      if (depth === 0) return content.slice(openIndex + 1, i);
    }
  }
  return content.slice(openIndex + 1);
}

/** True if `text` (trimmed) is nothing but a single quoted string literal with no interpolation -- i.e. genuinely static, not attacker-influenceable. */
export function isStaticStringLiteral(text: string): boolean {
  const trimmed = text.trim().replace(/;$/, "");
  if (/^(["'])(?:(?!\1)[^\\]|\\.)*\1$/.test(trimmed)) return true;
  if (/^`(?:[^`$\\]|\\.)*`$/.test(trimmed)) return true; // backtick with no ${...}
  return false;
}

/** Extracts the RHS text of a simple single-line-ish assignment (`lhs = rhs;`) starting search from `fromIndex`, up to the next unescaped `;` or newline. */
export function extractAssignmentRhs(content: string, equalsIndex: number): string {
  let end = equalsIndex + 1;
  while (end < content.length && content[end] !== ";" && content[end] !== "\n") end++;
  return content.slice(equalsIndex + 1, end);
}
