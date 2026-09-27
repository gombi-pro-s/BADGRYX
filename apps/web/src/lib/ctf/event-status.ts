// Pure event-window classification, shared by the server-rendered /ctf
// list badge (a static snapshot at render time) and the client-side
// ticking countdown (lib/mentor's own "pure logic vs I/O" split, applied
// here since this needs to run both server- and client-side).
export type CtfEventStatus = "upcoming" | "live" | "ended";

export function ctfEventStatus(startsAt: string | null, endsAt: string | null, now: number = Date.now()): CtfEventStatus {
  const startsMs = startsAt ? new Date(startsAt).getTime() : null;
  const endsMs = endsAt ? new Date(endsAt).getTime() : null;
  if (startsMs !== null && now < startsMs) return "upcoming";
  if (endsMs !== null && now >= endsMs) return "ended";
  return "live";
}
