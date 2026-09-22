"use client";

import { useActionState, useTransition } from "react";
import { createArtifactAction, deleteArtifactAction, type FormState } from "../actions";
import { Button } from "@/components/ui/button";
import { FormError, Label } from "@/components/ui/input";
import type { InvestigationArtifactType } from "@/types/database";

const initialState: FormState = { error: null };

const ARTIFACT_TYPES: { value: InvestigationArtifactType; label: string }[] = [
  { value: "whois_record", label: "WHOIS record" },
  { value: "email_headers", label: "Email headers" },
  { value: "social_media_profile", label: "Social media profile" },
  { value: "file_metadata", label: "File metadata" },
  { value: "log_excerpt", label: "Log excerpt" },
  { value: "network_capture_summary", label: "Network capture summary" },
  { value: "document_excerpt", label: "Document excerpt" },
  { value: "chat_transcript", label: "Chat transcript" },
];

interface Artifact {
  id: string;
  artifact_type: InvestigationArtifactType;
  title: string;
  content: string;
}

export function ArtifactsManager({ investigationId, artifacts }: { investigationId: string; artifacts: Artifact[] }) {
  const action = createArtifactAction.bind(null, investigationId);
  const [state, formAction, pending] = useActionState(action, initialState);
  const [deletePending, startDelete] = useTransition();

  return (
    <div>
      <p className="mb-3 text-xs text-foreground-subtle">
        Artifacts are the case&apos;s public evidence -- visible to anyone who can see this investigation, same as a
        CTF challenge&apos;s description. Write real, realistic content (not a placeholder) -- this is what the
        learner actually investigates.
      </p>

      {artifacts.length > 0 ? (
        <ul className="mb-6 space-y-2">
          {artifacts.map((artifact) => (
            <li key={artifact.id} className="rounded-md border border-border p-3">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs font-medium text-foreground-subtle uppercase">{artifact.artifact_type.replace(/_/g, " ")}</p>
                  <p className="text-sm font-medium text-foreground">{artifact.title}</p>
                </div>
                <button
                  type="button"
                  disabled={deletePending}
                  onClick={() => startDelete(() => deleteArtifactAction(investigationId, artifact.id))}
                  className="shrink-0 text-xs text-danger hover:underline disabled:opacity-50"
                >
                  Remove
                </button>
              </div>
              <pre className="mt-2 max-h-32 overflow-y-auto rounded-md bg-background-subtle p-2 font-mono text-xs whitespace-pre-wrap text-foreground-muted">
                {artifact.content}
              </pre>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mb-6 text-sm text-foreground-muted">No artifacts yet -- there&apos;s no case to investigate without at least one.</p>
      )}

      <form action={formAction} className="space-y-3 rounded-md border border-dashed border-border p-3">
        <div className="grid gap-3 sm:grid-cols-2">
          <div>
            <Label htmlFor="artifact_type">Artifact type</Label>
            <select
              id="artifact_type"
              name="artifact_type"
              className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
            >
              {ARTIFACT_TYPES.map((t) => (
                <option key={t.value} value={t.value}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="artifact_title">Title</Label>
            <input
              id="artifact_title"
              name="title"
              required
              maxLength={200}
              className="h-10 w-full rounded-md border border-border bg-surface px-3 text-sm text-foreground focus-visible:outline-2 focus-visible:outline-accent"
            />
          </div>
        </div>
        <div>
          <Label htmlFor="artifact_content">Content</Label>
          <textarea
            id="artifact_content"
            name="content"
            required
            rows={6}
            maxLength={20000}
            className="w-full resize-y rounded-md border border-border bg-surface px-3 py-2 font-mono text-xs text-foreground focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
        <FormError>{state.error}</FormError>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Adding..." : "Add artifact"}
        </Button>
      </form>
    </div>
  );
}
