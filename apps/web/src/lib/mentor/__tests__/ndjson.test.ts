import { describe, expect, it } from "vitest";
import { parseNdjsonLines } from "../ndjson";

describe("parseNdjsonLines", () => {
  it("parses a single complete line and leaves no remainder", () => {
    const { events, remainder } = parseNdjsonLines('{"type":"delta","text":"hi"}\n');
    expect(events).toEqual([{ type: "delta", text: "hi" }]);
    expect(remainder).toBe("");
  });

  it("parses multiple complete lines in one chunk", () => {
    const { events, remainder } = parseNdjsonLines(
      '{"type":"delta","text":"a"}\n{"type":"delta","text":"b"}\n{"type":"delta","text":"c"}\n',
    );
    expect(events).toEqual([
      { type: "delta", text: "a" },
      { type: "delta", text: "b" },
      { type: "delta", text: "c" },
    ]);
    expect(remainder).toBe("");
  });

  it("holds back an incomplete trailing line as the remainder", () => {
    const { events, remainder } = parseNdjsonLines('{"type":"delta","text":"a"}\n{"type":"delta","te');
    expect(events).toEqual([{ type: "delta", text: "a" }]);
    expect(remainder).toBe('{"type":"delta","te');
  });

  it("reassembles a line split across two chunks when remainder is prepended to the next chunk", () => {
    const first = parseNdjsonLines('{"type":"delta","te');
    expect(first.events).toEqual([]);
    expect(first.remainder).toBe('{"type":"delta","te');

    const second = parseNdjsonLines(first.remainder + 'xt":"hello"}\n');
    expect(second.events).toEqual([{ type: "delta", text: "hello" }]);
    expect(second.remainder).toBe("");
  });

  it("skips blank lines without erroring", () => {
    const { events, remainder } = parseNdjsonLines('{"type":"delta","text":"a"}\n\n{"type":"delta","text":"b"}\n');
    expect(events).toEqual([
      { type: "delta", text: "a" },
      { type: "delta", text: "b" },
    ]);
    expect(remainder).toBe("");
  });

  it("parses the terminal done and error event shapes", () => {
    const { events } = parseNdjsonLines(
      '{"type":"done","conversationId":"abc","quota":{"used":1,"limit":10,"allowed":true}}\n{"type":"error","error":"boom"}\n',
    );
    expect(events).toEqual([
      { type: "done", conversationId: "abc", quota: { used: 1, limit: 10, allowed: true } },
      { type: "error", error: "boom" },
    ]);
  });

  it("returns no events for an empty buffer", () => {
    const { events, remainder } = parseNdjsonLines("");
    expect(events).toEqual([]);
    expect(remainder).toBe("");
  });
});
