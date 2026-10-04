import { NextResponse } from "next/server";
import { z } from "zod";
import { requireApiUser } from "@/lib/auth/api";
import { environmentSpecSchema } from "@/lib/terminal/spec";

const paramsSchema = z.object({ labId: z.uuid() });

const bodySchema = z.object({
  variant_seed: z.coerce.number().int().min(0).max(9999),
  spec_json: z.string().trim().min(1, "Spec JSON is required."),
});

/**
 * The mobile-only equivalent of `admin/labs/[labId]/environment-manager.tsx`'s
 * `saveEnvironmentAction` -- exists for exactly one reason: that Server
 * Action validates the submitted spec against `environmentSpecSchema`
 * (the same schema `lib/terminal/execute.ts` parses it with) before ever
 * saving it, and the database's own `lab_environments_spec_is_object`
 * constraint only checks the column is a JSON object, nothing about its
 * actual shape. A plain Postgrest upsert from mobile would skip that
 * validation entirely, letting an admin save a spec that silently breaks
 * a learner's terminal. This route reuses the exact same TS schema so the
 * two clients can never validate a spec differently.
 *
 * RLS (`lab_environments_staff_only`, `FOR ALL`) is still the real
 * authorization boundary: `requireApiUser` only proves who's calling,
 * same as every other Bearer-authed route in this app -- the upsert below
 * runs through that user's own RLS-scoped client and fails for a
 * non-staff caller exactly the way a direct Postgrest write would.
 * Listing and deleting a lab's environments need no such validation, so
 * mobile does those as plain Postgrest calls and never hits this route.
 */
export async function POST(request: Request, { params }: { params: Promise<{ labId: string }> }) {
  const auth = await requireApiUser(request);
  if ("unauthorized" in auth) return auth.unauthorized;
  const { supabase } = auth;

  const parsedParams = paramsSchema.safeParse(await params);
  if (!parsedParams.success) {
    return NextResponse.json({ error: "Invalid lab id." }, { status: 400 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Request body must be JSON." }, { status: 400 });
  }

  const parsedBody = bodySchema.safeParse(body);
  if (!parsedBody.success) {
    return NextResponse.json({ error: parsedBody.error.issues[0]?.message ?? "Invalid input." }, { status: 400 });
  }

  let rawSpec: unknown;
  try {
    rawSpec = JSON.parse(parsedBody.data.spec_json);
  } catch {
    return NextResponse.json({ error: "Spec is not valid JSON." }, { status: 400 });
  }

  const specParsed = environmentSpecSchema.safeParse(rawSpec);
  if (!specParsed.success) {
    const issue = specParsed.error.issues[0];
    return NextResponse.json(
      { error: `Spec failed validation: ${issue?.message} (at ${issue?.path.join(".")})` },
      { status: 400 },
    );
  }

  const { error } = await supabase.from("lab_environments").upsert(
    {
      lab_id: parsedParams.data.labId,
      variant_seed: parsedBody.data.variant_seed,
      spec: specParsed.data as unknown as Record<string, unknown>,
    },
    { onConflict: "lab_id,variant_seed" },
  );
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json({ ok: true });
}
