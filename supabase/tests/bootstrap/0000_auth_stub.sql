-- ============================================================================
-- LOCAL TEST-ONLY BOOTSTRAP
-- ============================================================================
-- This file is NEVER applied to a real Supabase project. A real Supabase
-- project already provisions the `auth` schema (GoTrue), the `anon` /
-- `authenticated` / `service_role` Postgres roles, and the `auth.uid()` /
-- `auth.role()` / `auth.jwt()` helper functions that our RLS policies call.
--
-- Because this sandbox has no Docker daemon (so `supabase start` cannot run
-- the full local stack), we stand up a minimal stand-in of that surface
-- against a plain local Postgres instance so migrations and RLS policies can
-- be applied and tested for real instead of being written blind.
--
-- Roles (anon/authenticated/service_role/authenticator) are created by
-- scripts/local-test-db.sh before this file runs.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS auth;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  aud text NOT NULL DEFAULT 'authenticated',
  role text NOT NULL DEFAULT 'authenticated',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON auth.users TO anon, authenticated, service_role;

-- auth.uid(): current user id from the PostgREST JWT claim, matching
-- Supabase's real implementation.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
  LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::json->>'sub', '')::uuid
$$;

-- auth.role(): current Postgres/JWT role, matching Supabase's real
-- implementation.
CREATE OR REPLACE FUNCTION auth.role() RETURNS text
  LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::json->>'role', '')::text
$$;

-- auth.jwt(): full decoded claims object, matching Supabase's real
-- implementation.
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
  LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true), '')::jsonb
$$;

-- A real Supabase project's platform bootstrap grants baseline table/
-- sequence privileges in the `public` schema to anon/authenticated/
-- service_role at project-creation time -- RLS policies are what actually
-- restrict *rows*; the grant only governs whether the operation is
-- reachable at all. Application migrations never need to (and should not)
-- repeat this grant per table; we replicate the one-time platform grant here
-- so a plain local Postgres behaves like a real Supabase project for
-- everything applied after this file.
--
-- Deliberately NOT done for functions: vanilla PostgreSQL already grants
-- EXECUTE on every newly created function to PUBLIC by default (functions
-- differ from tables/sequences in this respect), and every role is
-- implicitly a member of PUBLIC -- so anon/authenticated already have
-- EXECUTE on any function unless a migration explicitly revokes it. Adding
-- a default-privilege rule here would grant an extra, independent ACL entry
-- to anon/authenticated that a plain `REVOKE ... FROM public` cannot undo,
-- which does not reflect how a real Supabase project behaves and would
-- silently defeat the REVOKE-then-GRANT-specific-role pattern used for
-- every SECURITY DEFINER function in this schema (record_skill_evidence,
-- log_audit_event, etc).
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
