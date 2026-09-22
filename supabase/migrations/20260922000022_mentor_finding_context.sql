-- ============================================================================
-- Adds 'finding' as a Mentor focus context. RELEASE_CHECKLIST.md's
-- EXPLAIN_FINDING mode entry had gone stale: its prompt instructions said
-- "this platform's security scanner ... [is] not implemented yet," which
-- was true when that mode was first stubbed but has not been true since
-- the scanner (schema, rule engine, AI enrichment, UI) actually shipped.
-- A learner's own scan_findings rows are real, owner-scoped data -- exactly
-- the kind of thing the Mentor is meant to ground itself in, the same way
-- it already does for labs/CTF/investigations. This migration is
-- schema-only, identical in shape to the earlier 'investigation' addition.
-- ============================================================================

ALTER TYPE public.mentor_context_type ADD VALUE 'finding';
