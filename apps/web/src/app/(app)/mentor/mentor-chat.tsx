"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import type { MentorContextType, MentorMode } from "@/types/database";
import type { MentorQuota } from "@/lib/mentor/rate-limit";

interface Message {
  role: "user" | "assistant";
  content: string;
}

const MODES: { value: MentorMode; label: string }[] = [
  { value: "explain", label: "Explain" },
  { value: "hint", label: "Hint" },
  { value: "teach", label: "Teach" },
  { value: "analyze_failure", label: "Analyze a failure" },
];

export function MentorChat({
  conversationId: initialConversationId,
  initialMessages,
  contextType,
  contextId,
  initialQuota,
}: {
  conversationId: string | null;
  initialMessages: Message[];
  contextType: MentorContextType;
  contextId: string | null;
  initialQuota: MentorQuota;
}) {
  const [conversationId, setConversationId] = useState(initialConversationId);
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [mode, setMode] = useState<MentorMode>("explain");
  const [input, setInput] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [quota, setQuota] = useState(initialQuota);

  async function send() {
    const trimmed = input.trim();
    if (!trimmed || pending) return;

    setPending(true);
    setError(null);
    setMessages((prev) => [...prev, { role: "user", content: trimmed }]);
    setInput("");

    try {
      const res = await fetch("/api/mentor/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          conversationId: conversationId ?? undefined,
          mode,
          message: trimmed,
          contextType,
          contextId: contextId ?? undefined,
        }),
      });
      const body = await res.json();
      if (!res.ok) {
        throw new Error(body.error ?? "Something went wrong.");
      }
      setConversationId(body.conversationId);
      setQuota(body.quota);
      setMessages((prev) => [...prev, { role: "assistant", content: body.message }]);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong.");
      // Roll back the optimistic user message on failure so retrying doesn't duplicate it.
      setMessages((prev) => prev.slice(0, -1));
      setInput(trimmed);
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="flex flex-1 flex-col overflow-hidden rounded-lg border border-border bg-surface">
      <div className="flex items-center justify-between border-b border-border px-4 py-2">
        <div className="flex gap-1.5">
          {MODES.map((m) => (
            <button
              key={m.value}
              type="button"
              onClick={() => setMode(m.value)}
              className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${
                mode === m.value ? "bg-accent-muted text-accent" : "text-foreground-muted hover:bg-background-subtle"
              }`}
            >
              {m.label}
            </button>
          ))}
        </div>
        <span className="text-xs text-foreground-subtle">
          {quota.used}/{quota.limit} today
        </span>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto p-4">
        {messages.length === 0 && (
          <p className="text-sm text-foreground-subtle">
            Ask a question below. The Mentor only knows what&apos;s in your real Skill Graph and progress
            &mdash; it won&apos;t invent lab state or hand out flags.
          </p>
        )}
        {messages.map((m, i) => (
          <div key={i} className={m.role === "user" ? "text-right" : ""}>
            <div
              className={`inline-block max-w-[85%] rounded-lg px-3 py-2 text-sm whitespace-pre-wrap ${
                m.role === "user" ? "bg-accent text-accent-foreground" : "bg-background-subtle text-foreground"
              }`}
            >
              {m.content}
            </div>
          </div>
        ))}
        {pending && <p className="text-xs text-foreground-subtle">Thinking...</p>}
      </div>

      {error && <p className="border-t border-danger/30 bg-danger-muted px-4 py-2 text-sm text-danger">{error}</p>}

      <div className="flex gap-2 border-t border-border p-3">
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
          rows={2}
          placeholder="Ask the Mentor..."
          className="flex-1 resize-none rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
        />
        <Button type="button" disabled={pending || !input.trim()} onClick={send}>
          Send
        </Button>
      </div>
    </div>
  );
}
