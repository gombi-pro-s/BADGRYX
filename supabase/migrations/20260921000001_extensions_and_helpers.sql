-- ============================================================================
-- Extensions and generic helper functions used across the schema.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid(), digest()
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- fuzzy search (skills, content)
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive usernames/emails

-- Generic "touch updated_at on row update" trigger, reused by every table
-- that has an updated_at column.
CREATE OR REPLACE FUNCTION public.set_updated_at()
  RETURNS trigger
  LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
  'Trigger function: sets updated_at = now() on every UPDATE.';
