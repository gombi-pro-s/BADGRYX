import type { Metadata } from "next";

export const metadata: Metadata = { title: "Offline" };

export default function OfflinePage() {
  return (
    <div className="mx-auto max-w-md px-6 py-16 text-center">
      <h1 className="text-xl font-semibold text-foreground">You&apos;re offline</h1>
      <p className="mt-2 text-sm text-foreground-muted">
        iCorePen needs a live connection for almost everything -- lessons, labs, CTF, and Mentor all read and
        write real data from the server. Reconnect and reload to keep going.
      </p>
    </div>
  );
}
