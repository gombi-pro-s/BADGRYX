"use client";

import { useEffect, useState } from "react";
import { ctfEventStatus } from "@/lib/ctf/event-status";

function formatDuration(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const parts: string[] = [];
  if (days > 0) parts.push(`${days}d`);
  if (days > 0 || hours > 0) parts.push(`${hours}h`);
  if (days === 0) {
    parts.push(`${minutes}m`);
    parts.push(`${seconds}s`);
  } else if (hours > 0) {
    parts.push(`${minutes}m`);
  }
  return parts.join(" ");
}

export function EventStatusBanner({ startsAt, endsAt }: { startsAt: string | null; endsAt: string | null }) {
  const [now, setNow] = useState<number | null>(null);

  // Only ever calls setState from the interval's own callback, never
  // synchronously in the effect body -- the first real tick lands within
  // 1s of mount, an acceptable trade for not fighting the timer to also
  // fire immediately (see react-hooks/set-state-in-effect).
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  // Nothing to tick if the event has no time window at all.
  if (!startsAt && !endsAt) return null;
  // Avoids a server/client clock mismatch on first paint.
  if (now === null) return null;

  const status = ctfEventStatus(startsAt, endsAt, now);

  if (status === "upcoming") {
    const startsMs = new Date(startsAt as string).getTime();
    return (
      <div className="rounded-lg border border-accent/30 bg-accent-muted px-4 py-3 text-sm font-medium text-accent">
        Starts in {formatDuration(startsMs - now)}
      </div>
    );
  }
  if (status === "ended") {
    return (
      <div className="rounded-lg border border-border bg-background-subtle px-4 py-3 text-sm font-medium text-foreground-muted">
        Ended
      </div>
    );
  }
  if (endsAt) {
    const endsMs = new Date(endsAt).getTime();
    return (
      <div className="rounded-lg border border-success/30 bg-success-muted px-4 py-3 text-sm font-medium text-success">
        Live -- ends in {formatDuration(endsMs - now)}
      </div>
    );
  }
  return (
    <div className="rounded-lg border border-success/30 bg-success-muted px-4 py-3 text-sm font-medium text-success">
      Live
    </div>
  );
}
