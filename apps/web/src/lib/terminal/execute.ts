import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database";
import { createAdminClient } from "@/lib/supabase/admin";
import { executeCommand } from "./interpreter";
import { environmentSpecSchema, initialTerminalState, type TerminalState } from "./spec";

export class TerminalError extends Error {}

const COMMAND_MAX_LENGTH = 2000;

export interface TerminalExecutionResult {
  output: string;
  cwd: string;
  user: string;
  hostname: string;
}

function parseState(raw: unknown, fallback: TerminalState): TerminalState {
  if (
    raw &&
    typeof raw === "object" &&
    typeof (raw as Record<string, unknown>).cwd === "string" &&
    typeof (raw as Record<string, unknown>).user === "string" &&
    Array.isArray((raw as Record<string, unknown>).discovered)
  ) {
    const r = raw as { cwd: string; user: string; discovered: unknown[] };
    return { cwd: r.cwd, user: r.user, discovered: r.discovered.filter((d): d is string => typeof d === "string") };
  }
  return fallback;
}

/**
 * Runs one terminal command for a lab instance. See ADR 0009 for the full
 * design reasoning; in short: this reads lab_instances through the
 * caller's OWN session first (proving ownership via the same RLS the rest
 * of the app relies on), and only after that succeeds does it escalate --
 * via createAdminClient(), narrowly, for this one read -- to fetch the
 * environment spec, which RLS otherwise locks to staff only. The spec
 * itself, and any file content the command didn't touch, never leave this
 * function; only the rendered output of the one command requested does.
 */
export async function runTerminalCommand(
  supabase: SupabaseClient<Database>,
  userId: string,
  labInstanceId: string,
  commandLine: string,
): Promise<TerminalExecutionResult> {
  if (commandLine.length > COMMAND_MAX_LENGTH) {
    throw new TerminalError(`Command is too long (max ${COMMAND_MAX_LENGTH} characters).`);
  }

  const { data: instance, error: instanceError } = await supabase
    .from("lab_instances")
    .select("id, lab_id, user_id, status, variant_seed, environment_state")
    .eq("id", labInstanceId)
    .maybeSingle();
  if (instanceError) throw new Error(`Failed to load lab instance: ${instanceError.message}`);
  if (!instance || instance.user_id !== userId) {
    throw new TerminalError("Lab instance not found.");
  }
  if (instance.status !== "running") {
    throw new TerminalError("This lab instance isn't running.");
  }

  const admin = createAdminClient();
  const { data: environment, error: environmentError } = await admin
    .from("lab_environments")
    .select("spec")
    .eq("lab_id", instance.lab_id)
    .eq("variant_seed", instance.variant_seed)
    .maybeSingle();
  if (environmentError) throw new Error(`Failed to load lab environment: ${environmentError.message}`);
  if (!environment) {
    throw new TerminalError("This lab doesn't have a terminal environment.");
  }

  const parsedSpec = environmentSpecSchema.safeParse(environment.spec);
  if (!parsedSpec.success) {
    throw new Error(`Lab environment spec is invalid: ${parsedSpec.error.issues[0]?.message}`);
  }
  const spec = parsedSpec.data;

  const state = parseState(instance.environment_state, initialTerminalState(spec));
  const cwdBefore = state.cwd;
  const { output, state: newState } = executeCommand(spec, state, commandLine);

  const { error: updateError } = await supabase
    .from("lab_instances")
    // TerminalState has known fields, not an index signature -- jsonb
    // storage doesn't care about that distinction, so this cast is just
    // bridging our app-level shape to the column's generic Record type.
    .update({ environment_state: newState as unknown as Record<string, unknown> })
    .eq("id", instance.id);
  if (updateError) throw new Error(`Failed to persist terminal state: ${updateError.message}`);

  // An empty command is used by the client as a silent "connect" call to
  // learn the initial prompt (cwd/user/hostname) before any real command
  // has run -- not worth cluttering the transcript with.
  if (commandLine.trim().length > 0) {
    const { error: logError } = await supabase.from("lab_terminal_commands").insert({
      lab_instance_id: instance.id,
      user_id: userId,
      command: commandLine,
      output,
      cwd_before: cwdBefore,
      cwd_after: newState.cwd,
    });
    if (logError) console.error("Failed to log terminal command:", logError);
  }

  return { output, cwd: newState.cwd, user: newState.user, hostname: spec.hostname };
}
