# iCorePen Mobile

The Flutter app itself lives in [`app/`](./app/README.md) -- see that
README for setup, configuration, and what's honestly built so far versus
still ahead. See [ADR 0026](../docs/adr/0026-flutter-mobile-foundation.md)
for the design decisions.

No mobile-specific backend logic exists or is needed -- the RLS policies
and `SECURITY DEFINER` grading functions in `supabase/migrations/` are the
shared contract both `apps/web` and this client call directly against the
same Supabase project.
