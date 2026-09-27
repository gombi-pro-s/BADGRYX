/**
 * Pure: parses `Authorization: Bearer <token>` from a Route Handler's
 * request headers. No I/O, unit-tested directly -- see
 * lib/supabase/route-handler.ts for how the extracted token is actually
 * used to authenticate a non-browser client (mobile/app) against the
 * exact same RLS a cookie-based web session gets.
 */
export function extractBearerToken(authorizationHeader: string | null): string | null {
  if (!authorizationHeader) return null;
  const match = /^Bearer\s+(.+)$/i.exec(authorizationHeader.trim());
  if (!match) return null;
  const token = match[1].trim();
  return token.length > 0 ? token : null;
}
