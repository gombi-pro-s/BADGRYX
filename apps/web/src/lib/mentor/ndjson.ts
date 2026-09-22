/**
 * Pure newline-delimited-JSON parsing for the Mentor's streaming chat
 * response (POST /api/mentor/chat). No I/O, so it's unit-testable without
 * a real stream -- mirrors lib/billing/stripe.ts vs stripe-client.ts.
 *
 * A network chunk boundary can land in the middle of a JSON line, so the
 * caller accumulates chunks into a buffer and calls this on each new
 * chunk; only complete (newline-terminated) lines are parsed, and
 * whatever's left after the last newline is returned as `remainder` for
 * the caller to prepend to the next chunk.
 */
export function parseNdjsonLines(buffer: string): { events: unknown[]; remainder: string } {
  const events: unknown[] = [];
  let rest = buffer;

  let newlineIndex: number;
  while ((newlineIndex = rest.indexOf("\n")) !== -1) {
    const line = rest.slice(0, newlineIndex);
    rest = rest.slice(newlineIndex + 1);
    if (!line) continue;
    events.push(JSON.parse(line));
  }

  return { events, remainder: rest };
}

export type MentorStreamEvent =
  | { type: "delta"; text: string }
  | { type: "done"; conversationId: string; quota: { used: number; limit: number; allowed: boolean } }
  | { type: "error"; error: string };
