import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { buildMentorContext, ALL_MENTOR_CONTEXT_TYPES } from "@/lib/mentor/context";
import { checkMentorQuota } from "@/lib/mentor/rate-limit";
import { streamMentorReply, type MentorTurn } from "@/lib/mentor/client";
import type { MentorStreamEvent } from "@/lib/mentor/ndjson";
import type { MentorContextType, MentorMode } from "@/types/database";

const MENTOR_MODES: MentorMode[] = [
  "explain",
  "hint",
  "teach",
  "analyze_failure",
  "explain_command",
  "explain_finding",
  "explain_code",
  "guide_investigation",
  "review_methodology",
  "generate_quiz",
  "prepare_assessment",
  "explain_remediation",
  "review_report",
];
const requestSchema = z.object({
  conversationId: z.uuid().optional(),
  mode: z.enum(MENTOR_MODES as [MentorMode, ...MentorMode[]]),
  message: z.string().trim().min(1).max(4000),
  contextType: z.enum(ALL_MENTOR_CONTEXT_TYPES as [MentorContextType, ...MentorContextType[]]).default("general"),
  contextId: z.uuid().optional(),
});

export async function POST(request: Request) {
  const user = await requireUser();

  const body = await request.json().catch(() => null);
  const parsed = requestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: parsed.error.issues[0]?.message ?? "Invalid request." }, { status: 400 });
  }
  const { conversationId, mode, message, contextType, contextId } = parsed.data;

  const supabase = await createClient();

  const quota = await checkMentorQuota(supabase, user.id);
  if (!quota.allowed) {
    return NextResponse.json(
      { error: `Daily Mentor request limit reached (${quota.used}/${quota.limit}). Try again tomorrow, or upgrade your plan.` },
      { status: 429 },
    );
  }

  // Resolve or create the conversation -- RLS (mentor_conversations_select_own_or_staff /
  // insert_own) is the real boundary; these queries just can't see/create
  // anything outside what RLS already permits for this user.
  let resolvedConversationId = conversationId;
  if (resolvedConversationId) {
    const { data: existing } = await supabase
      .from("mentor_conversations")
      .select("id")
      .eq("id", resolvedConversationId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!existing) {
      return NextResponse.json({ error: "Conversation not found." }, { status: 404 });
    }
  } else {
    const { data: created, error: createError } = await supabase
      .from("mentor_conversations")
      .insert({
        user_id: user.id,
        context_type: contextType,
        context_id: contextId ?? null,
        title: message.slice(0, 80),
      })
      .select("id")
      .single();
    if (createError || !created) {
      return NextResponse.json({ error: "Could not start a conversation." }, { status: 500 });
    }
    resolvedConversationId = created.id;
  }

  const { data: historyRows } = await supabase
    .from("mentor_messages")
    .select("role, content")
    .eq("conversation_id", resolvedConversationId)
    .order("created_at", { ascending: true });
  const history: MentorTurn[] = (historyRows ?? []).map((row) => ({ role: row.role, content: row.content }));

  const context = await buildMentorContext(supabase, user.id, contextType, contextId ?? null);

  // Streams the response as newline-delimited JSON events -- {type:"delta"}
  // per text chunk as Anthropic produces it, then a single terminal
  // {type:"done"} (with conversationId/quota, mirroring the old single JSON
  // response) or {type:"error"}. DB persistence happens once the full text
  // is known, after the stream completes -- the client sees text arrive
  // token-by-token well before that.
  const encoder = new TextEncoder();
  const responseStream = new ReadableStream<Uint8Array>({
    async start(controller) {
      function send(event: MentorStreamEvent) {
        controller.enqueue(encoder.encode(JSON.stringify(event) + "\n"));
      }

      let assistantText: string;
      try {
        assistantText = await streamMentorReply({ mode, context, history, newUserMessage: message }, (delta) =>
          send({ type: "delta", text: delta }),
        );
      } catch (err) {
        console.error("Mentor call failed:", err);
        send({ type: "error", error: "The Mentor is temporarily unavailable. Please try again shortly." });
        controller.close();
        return;
      }

      const { error: userMsgError } = await supabase.from("mentor_messages").insert({
        conversation_id: resolvedConversationId,
        user_id: user.id,
        role: "user",
        mode,
        content: message,
      });
      const { error: assistantMsgError } = await supabase.from("mentor_messages").insert({
        conversation_id: resolvedConversationId,
        user_id: user.id,
        role: "assistant",
        mode,
        content: assistantText,
      });
      if (userMsgError || assistantMsgError) {
        console.error("Failed to persist Mentor message:", userMsgError ?? assistantMsgError);
      }

      await supabase.rpc("log_audit_event", {
        p_action: "mentor.message.sent",
        p_target_type: "mentor_conversation",
        p_target_id: resolvedConversationId,
        p_metadata: { mode },
      });

      const usedAfterThisMessage = quota.used + 1;
      send({
        type: "done",
        conversationId: resolvedConversationId,
        quota: { used: usedAfterThisMessage, limit: quota.limit, allowed: usedAfterThisMessage < quota.limit },
      });
      controller.close();
    },
  });

  return new Response(responseStream, { headers: { "Content-Type": "application/x-ndjson; charset=utf-8" } });
}
