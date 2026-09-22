import type { Metadata } from "next";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { checkMentorQuota } from "@/lib/mentor/rate-limit";
import type { MentorContextType } from "@/types/database";
import { MentorChat } from "./mentor-chat";

export const metadata: Metadata = { title: "AI Mentor" };

const VALID_CONTEXT_TYPES: MentorContextType[] = ["skill", "lesson", "lab", "ctf", "general"];

export default async function MentorPage({
  searchParams,
}: {
  searchParams: Promise<{ contextType?: string; contextId?: string }>;
}) {
  const { contextType: rawContextType, contextId } = await searchParams;
  const contextType: MentorContextType = VALID_CONTEXT_TYPES.includes(rawContextType as MentorContextType)
    ? (rawContextType as MentorContextType)
    : "general";

  const user = await requireUser();
  const supabase = await createClient();

  const [{ data: focusTitle }, quota] = await Promise.all([
    resolveFocusTitle(supabase, contextType, contextId),
    checkMentorQuota(supabase, user.id),
  ]);

  let conversationId: string | null = null;
  let initialMessages: { role: "user" | "assistant"; content: string }[] = [];

  const conversationQuery = supabase
    .from("mentor_conversations")
    .select("id")
    .eq("user_id", user.id)
    .eq("context_type", contextType)
    .order("updated_at", { ascending: false })
    .limit(1);
  const { data: existingConversation } = contextId
    ? await conversationQuery.eq("context_id", contextId).maybeSingle()
    : await conversationQuery.is("context_id", null).maybeSingle();

  if (existingConversation) {
    conversationId = existingConversation.id;
    const { data: messages } = await supabase
      .from("mentor_messages")
      .select("role, content")
      .eq("conversation_id", existingConversation.id)
      .order("created_at", { ascending: true });
    initialMessages = messages ?? [];
  }

  return (
    <div className="mx-auto flex h-[calc(100vh-4rem)] max-w-3xl flex-col px-6 py-8">
      <div className="mb-4">
        <h1 className="text-xl font-semibold text-foreground">AI Security Mentor</h1>
        <p className="text-sm text-foreground-muted">
          {focusTitle ? `Focused on: ${focusTitle}` : "Ask about any concept, get a progressive hint, or review a recent failure."}
        </p>
      </div>
      <MentorChat
        conversationId={conversationId}
        initialMessages={initialMessages}
        contextType={contextType}
        contextId={contextId ?? null}
        initialQuota={quota}
      />
    </div>
  );
}

async function resolveFocusTitle(
  supabase: Awaited<ReturnType<typeof createClient>>,
  contextType: MentorContextType,
  contextId: string | undefined,
): Promise<{ data: string | null }> {
  if (!contextId || contextType === "general") return { data: null };

  if (contextType === "skill") {
    const { data } = await supabase.from("skills").select("name").eq("id", contextId).maybeSingle();
    return { data: data?.name ?? null };
  }
  if (contextType === "lab") {
    const { data } = await supabase.from("labs").select("title").eq("id", contextId).maybeSingle();
    return { data: data?.title ?? null };
  }
  if (contextType === "lesson") {
    const { data } = await supabase.from("lessons").select("title").eq("id", contextId).maybeSingle();
    return { data: data?.title ?? null };
  }
  if (contextType === "ctf") {
    const { data } = await supabase.from("ctf_challenges_public").select("title").eq("id", contextId).maybeSingle();
    return { data: data?.title ?? null };
  }
  return { data: null };
}
