import { NextResponse } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth/session";
import { createClient } from "@/lib/supabase/server";
import { runTerminalCommand, TerminalError } from "@/lib/terminal/execute";

const paramsSchema = z.object({ labInstanceId: z.uuid() });
const bodySchema = z.object({ command: z.string().max(2000) });

export async function POST(request: Request, { params }: { params: Promise<{ labInstanceId: string }> }) {
  const user = await requireUser();

  const parsedParams = paramsSchema.safeParse(await params);
  if (!parsedParams.success) {
    return NextResponse.json({ error: "Invalid lab instance id." }, { status: 400 });
  }

  const body = await request.json().catch(() => null);
  const parsedBody = bodySchema.safeParse(body);
  if (!parsedBody.success) {
    return NextResponse.json({ error: parsedBody.error.issues[0]?.message ?? "Invalid request." }, { status: 400 });
  }

  const supabase = await createClient();

  try {
    const result = await runTerminalCommand(supabase, user.id, parsedParams.data.labInstanceId, parsedBody.data.command);
    return NextResponse.json(result);
  } catch (err) {
    if (err instanceof TerminalError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error("Terminal command failed:", err);
    return NextResponse.json({ error: "The terminal is temporarily unavailable. Please try again shortly." }, { status: 502 });
  }
}
