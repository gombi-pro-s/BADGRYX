# iCorePen Mobile (planned)

Not started yet. When built, this will be a Flutter/Dart app consuming the
same Supabase project as `apps/web` (see
[`docs/adr/0001-supabase-over-firebase.md`](../docs/adr/0001-supabase-over-firebase.md)),
using the `supabase_flutter` package for Auth + Postgres access under the
same Row Level Security policies defined in `supabase/migrations/`.

No mobile-specific backend logic should be needed — the RLS policies and
`SECURITY DEFINER` grading functions in `supabase/migrations/` are the
shared contract both clients call directly.
