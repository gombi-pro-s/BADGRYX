import type { Metadata } from "next";
import Link from "next/link";
import { requireUser } from "@/lib/auth/session";
import { DeleteAccountForm } from "./delete-account-form";

export const metadata: Metadata = { title: "Privacy & data" };

export default async function PrivacyPage() {
  const user = await requireUser();

  return (
    <div className="mx-auto max-w-2xl px-6 py-10">
      <Link href="/settings" className="mb-4 inline-block text-xs text-foreground-subtle hover:text-foreground">
        &larr; Settings
      </Link>
      <h1 className="mb-1 text-2xl font-semibold text-foreground">Privacy &amp; data</h1>
      <p className="mb-8 text-sm text-foreground-muted">{user.email}</p>

      <div className="mb-6 rounded-lg border border-border bg-surface p-6">
        <h2 className="text-sm font-semibold text-foreground">Export your data</h2>
        <p className="mt-1 mb-4 text-xs text-foreground-subtle">
          Download everything tied to your account -- profile, skill graph, lab/quiz/CTF/investigation/capstone
          history, mentor conversations, scanner scans, and subscription history -- as a JSON file.
        </p>
        <a
          href="/api/account/export"
          download
          className="inline-flex h-10 items-center justify-center rounded-md bg-surface-raised border border-border px-4 text-sm font-medium text-foreground hover:border-border-strong"
        >
          Export my data
        </a>
      </div>

      <div className="rounded-lg border border-danger/30 bg-danger-muted p-6">
        <h2 className="text-sm font-semibold text-danger">Delete account</h2>
        <p className="mt-1 mb-4 text-xs text-foreground-subtle">
          Permanently deletes your account. This cannot be undone.
        </p>
        <DeleteAccountForm userEmail={user.email ?? ""} />
      </div>
    </div>
  );
}
