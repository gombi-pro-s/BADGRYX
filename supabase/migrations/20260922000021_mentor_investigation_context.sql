-- ============================================================================
-- Adds 'investigation' as a Mentor focus context. Every other content type
-- with its own learner-facing detail page (lesson, lab, ctf) already had an
-- "Ask Mentor" deep link wired to a real, grounded context.type; the
-- investigation workspace (/investigate/[investigationId]) did not, even
-- though buildMentorContext()/buildFocusDetail() and the MODE:
-- GUIDE_INVESTIGATION prompt instructions were already built and correct --
-- there was simply no context type value to reach them with, and no link to
-- get there. This migration is schema-only: the mentor_context_type enum
-- gains one more value, exactly like the earlier investigation/capstone
-- additions to skill_evidence_type.
-- ============================================================================

ALTER TYPE public.mentor_context_type ADD VALUE 'investigation';
