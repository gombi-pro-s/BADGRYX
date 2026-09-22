import "server-only";

import Anthropic from "@anthropic-ai/sdk";
import { getAnthropicApiKey } from "@/lib/env";
import type { MentorMode } from "@/types/database";
import { buildMentorSystemPrompt } from "./prompt";
import type { MentorContext } from "./context";

const MODEL = "claude-sonnet-5";
const MAX_TOKENS = 1024;
const MAX_HISTORY_TURNS = 12; // most recent turns, to keep requests bounded

export interface MentorTurn {
  role: "user" | "assistant";
  content: string;
}

/**
 * Calls Anthropic with the system prompt built from real user data
 * (buildMentorSystemPrompt/buildMentorContext) plus recent conversation
 * history and the new user message. The new message is passed as a
 * `messages` turn, never concatenated into the system prompt -- that
 * boundary is what lets the system instructions describe it as untrusted
 * input rather than trusted configuration.
 *
 * Streams token-by-token via the Anthropic SDK's `messages.stream()`
 * (`.on('text', ...)` fires each text delta as it arrives), so the caller
 * (the API route) can forward each delta to the client immediately instead
 * of waiting for the full response. `onDelta` is called synchronously for
 * each chunk; the function itself resolves once the full message is
 * complete, returning the same full text a non-streaming call would have.
 */
export async function streamMentorReply(
  params: {
    mode: MentorMode;
    context: MentorContext;
    history: MentorTurn[];
    newUserMessage: string;
  },
  onDelta: (text: string) => void,
): Promise<string> {
  const client = new Anthropic({ apiKey: getAnthropicApiKey() });

  const system = buildMentorSystemPrompt(params.mode, params.context);
  const trimmedHistory = params.history.slice(-MAX_HISTORY_TURNS);

  const stream = client.messages.stream({
    model: MODEL,
    max_tokens: MAX_TOKENS,
    system,
    messages: [
      ...trimmedHistory.map((turn) => ({ role: turn.role, content: turn.content })),
      { role: "user" as const, content: params.newUserMessage },
    ],
  });

  stream.on("text", onDelta);

  const finalMessage = await stream.finalMessage();
  const textBlock = finalMessage.content.find((block) => block.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new Error("Mentor response contained no text content.");
  }
  return textBlock.text;
}
