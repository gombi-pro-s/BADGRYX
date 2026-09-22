"use client";

import { useEffect, useRef, useState } from "react";

interface TranscriptEntry {
  command: string;
  output: string;
}

interface Prompt {
  user: string;
  hostname: string;
  cwd: string;
}

async function callTerminal(labInstanceId: string, command: string) {
  const res = await fetch(`/api/labs/${labInstanceId}/terminal`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ command }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(body.error ?? "The terminal is temporarily unavailable.");
  return body as { output: string; cwd: string; user: string; hostname: string };
}

function promptString(prompt: Prompt | null): string {
  if (!prompt) return "connecting...";
  return `${prompt.user}@${prompt.hostname}:${prompt.cwd}$`;
}

export function Terminal({
  labInstanceId,
  initialTranscript,
}: {
  labInstanceId: string;
  initialTranscript: TranscriptEntry[];
}) {
  const [transcript, setTranscript] = useState<TranscriptEntry[]>(initialTranscript);
  const [prompt, setPrompt] = useState<Prompt | null>(null);
  const [input, setInput] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [historyIndex, setHistoryIndex] = useState<number | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const commandHistory = transcript.map((t) => t.command);

  useEffect(() => {
    // A silent "connect" call (empty command) to learn the real cwd/user/
    // hostname before any visible command has run -- see
    // lib/terminal/execute.ts's doc comment on why an empty command is
    // treated specially (not logged to the transcript).
    let cancelled = false;
    callTerminal(labInstanceId, "")
      .then((result) => {
        if (!cancelled) setPrompt({ user: result.user, hostname: result.hostname, cwd: result.cwd });
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Could not connect to the terminal.");
      });
    return () => {
      cancelled = true;
    };
  }, [labInstanceId]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [transcript, pending]);

  async function runCommand() {
    const command = input.trim();
    if (!command || pending) return;

    if (command === "clear") {
      setTranscript([]);
      setInput("");
      setHistoryIndex(null);
      return;
    }

    setPending(true);
    setError(null);
    setInput("");
    setHistoryIndex(null);

    try {
      const result = await callTerminal(labInstanceId, command);
      setTranscript((prev) => [...prev, { command, output: result.output }]);
      setPrompt({ user: result.user, hostname: result.hostname, cwd: result.cwd });
    } catch (err) {
      setError(err instanceof Error ? err.message : "The terminal is temporarily unavailable.");
    } finally {
      setPending(false);
    }
  }

  function recallHistory(direction: -1 | 1) {
    if (commandHistory.length === 0) return;
    const nextIndex =
      historyIndex === null
        ? (direction === -1 ? commandHistory.length - 1 : null)
        : Math.min(Math.max(historyIndex + direction, 0), commandHistory.length - 1);
    if (nextIndex === null) {
      setHistoryIndex(null);
      setInput("");
      return;
    }
    setHistoryIndex(nextIndex);
    setInput(commandHistory[nextIndex]);
  }

  return (
    <div className="overflow-hidden rounded-lg border border-border bg-background">
      <div ref={scrollRef} className="max-h-96 space-y-2 overflow-y-auto p-4 font-mono text-xs">
        {transcript.length === 0 && (
          <p className="text-foreground-subtle">Connected. Type a command below -- try `help` to see what&apos;s available.</p>
        )}
        {transcript.map((entry, i) => (
          <div key={i}>
            <p className="text-accent">$ {entry.command}</p>
            {entry.output && <pre className="whitespace-pre-wrap text-foreground">{entry.output}</pre>}
          </div>
        ))}
        {pending && <p className="text-foreground-subtle">...</p>}
      </div>

      {error && (
        <p role="alert" className="border-t border-danger/30 bg-danger-muted px-4 py-2 text-xs text-danger">
          {error}
        </p>
      )}

      <div className="flex items-center gap-2 border-t border-border bg-surface px-3 py-2">
        <span className="shrink-0 font-mono text-xs text-foreground-subtle">{promptString(prompt)}</span>
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              runCommand();
            } else if (e.key === "ArrowUp") {
              e.preventDefault();
              recallHistory(-1);
            } else if (e.key === "ArrowDown") {
              e.preventDefault();
              recallHistory(1);
            }
          }}
          disabled={pending || !prompt}
          spellCheck={false}
          autoComplete="off"
          className="flex-1 bg-transparent font-mono text-xs text-foreground outline-none disabled:opacity-50"
          aria-label="Terminal command input"
        />
      </div>
    </div>
  );
}
