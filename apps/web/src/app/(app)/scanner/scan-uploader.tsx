"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/input";

type Mode = "paste" | "upload";

export function ScanUploader() {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("paste");
  const [filename, setFilename] = useState("snippet.js");
  const [content, setContent] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function runScan() {
    setPending(true);
    setError(null);
    try {
      let payloadFiles: { filename: string; content: string }[];
      if (mode === "paste") {
        if (!content.trim()) throw new Error("Paste some code first.");
        payloadFiles = [{ filename: filename.trim() || "snippet.txt", content }];
      } else {
        if (files.length === 0) throw new Error("Choose at least one file.");
        payloadFiles = await Promise.all(files.map(async (f) => ({ filename: f.name, content: await f.text() })));
      }

      const res = await fetch("/api/scanner/scan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          targetType: mode === "paste" ? "pasted_snippet" : "uploaded_files",
          files: payloadFiles,
        }),
      });
      const body = await res.json();
      if (!res.ok) throw new Error(body.error ?? "Scan failed.");
      router.push(`/scanner/${body.scanId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Scan failed.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="rounded-lg border border-border bg-surface p-6">
      <div className="mb-4 flex gap-1.5">
        <button
          type="button"
          onClick={() => setMode("paste")}
          className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${
            mode === "paste" ? "bg-accent-muted text-accent" : "text-foreground-muted hover:bg-background-subtle"
          }`}
        >
          Paste code
        </button>
        <button
          type="button"
          onClick={() => setMode("upload")}
          className={`rounded-full px-2.5 py-1 text-xs font-medium transition-colors ${
            mode === "upload" ? "bg-accent-muted text-accent" : "text-foreground-muted hover:bg-background-subtle"
          }`}
        >
          Upload files
        </button>
      </div>

      {mode === "paste" ? (
        <div className="space-y-3">
          <div>
            <Label htmlFor="scan-filename">Filename (used to detect the language)</Label>
            <input
              id="scan-filename"
              value={filename}
              onChange={(e) => setFilename(e.target.value)}
              placeholder="app.js"
              className="h-9 w-48 rounded-md border border-border bg-surface px-3 text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
            />
          </div>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={12}
            placeholder="Paste source code to scan..."
            className="w-full resize-y rounded-md border border-border bg-surface px-3 py-2 font-mono text-sm text-foreground placeholder:text-foreground-subtle focus-visible:outline-2 focus-visible:outline-accent"
          />
        </div>
      ) : (
        <div>
          <input
            type="file"
            multiple
            onChange={(e) => setFiles(Array.from(e.target.files ?? []))}
            className="block w-full text-sm text-foreground-muted file:mr-3 file:rounded-md file:border-0 file:bg-accent-muted file:px-3 file:py-2 file:text-sm file:font-medium file:text-accent"
          />
          {files.length > 0 && (
            <p className="mt-2 text-xs text-foreground-subtle">
              {files.length} file{files.length === 1 ? "" : "s"} selected: {files.map((f) => f.name).join(", ")}
            </p>
          )}
        </div>
      )}

      {error && (
        <p role="alert" className="mt-3 rounded-md border border-danger/30 bg-danger-muted px-3 py-2 text-sm text-danger">
          {error}
        </p>
      )}

      <div className="mt-4">
        <Button type="button" disabled={pending} onClick={runScan}>
          {pending ? "Scanning..." : "Run scan"}
        </Button>
      </div>
    </div>
  );
}
