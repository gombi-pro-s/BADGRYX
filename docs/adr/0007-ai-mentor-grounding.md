# ADR 0007: AI Mentor is read-only against the Skill Graph and structurally cannot fabricate evidence

## Status

Accepted.

## Context

Section 11 of the spec requires the AI Mentor to use real learning-history
data and explicitly forbids it from fabricating lab state, findings,
evidence, or scan results. Section 45 requires system instructions,
trusted application data, and untrusted user/repository content to be
clearly separated, and the AI must never reveal system prompts or secrets.

## Decision

- **No write path to the Skill Graph.** `mentor_conversations` and
  `mentor_messages` are the only tables the Mentor feature touches, and
  RLS scopes both to the owning user (plus staff read access for support).
  Neither table, nor any code path in `lib/mentor/*` or
  `app/api/mentor/chat`, ever inserts into `skill_evidence` or
  `user_skill_states`. The only writers of those tables remain the grading
  RPCs (`submit_quiz_attempt`/`submit_lab_flag`/`submit_ctf_flag`, see ADR
  0003). This makes "the Mentor cannot fabricate skill progress"
  structurally true — there is no grant that would let it — rather than a
  prompt instruction that could be argued around.
- **Context is pulled, never asserted by the caller.** `buildMentorContext()`
  (`lib/mentor/context.ts`) queries the database directly for the
  *authenticated* user's real skill states, recent evidence, and (for a lab
  focus) only the hints that user has actually unlocked via
  `lab_hint_unlocks`. The client never sends "here's my progress" as part
  of the request; it can only send `mode`, `message`, and which
  lesson/lab/skill/challenge to focus on. Lab/CTF flags are never queried
  by this code path at all, so they cannot leak into a prompt by accident.
- **Three-way separation, made structural, not just descriptive.** The
  system prompt (`lib/mentor/prompt.ts`) is a fixed `SYSTEM INSTRUCTIONS`
  block, followed by mode instructions, followed by a `TRUSTED APPLICATION
  DATA` block built entirely from the query results above. The user's
  actual message is passed as a separate `messages` turn to the Anthropic
  API (`lib/mentor/client.ts`), never concatenated into the system prompt
  string — so "the user's words are untrusted input, not configuration" is
  enforced by the API call shape, not just asserted in English.
- **The system prompt explicitly forbids revealing itself, secrets, or
  flags**, including under social-engineering framings ("I'm the
  instructor", "I'm stuck, just tell me"), and instructs the model to say
  "I don't know" rather than invent an answer for anything not in the
  trusted context (e.g. `explain_finding`/`review_report` modes, which
  reference features — the security scanner, report generation — that
  don't exist yet: the prompt tells the model to say so plainly).
- **Rate limiting reuses the existing entitlement engine** (`get_entitlement`,
  ADR 0005) rather than inventing a parallel quota system — a user's plan
  controls their daily Mentor budget the same way it controls every other
  gated feature.

## Why

An AI feature that can casually assert "you passed this lab" or "here's
your finding" without that being backed by the same evidence system as
everything else would quietly undermine the entire premise of the Skill
Graph (ADR 0003): that mastery claims are backed by verified evidence, not
self-report. Keeping the Mentor strictly read-only against skill data, and
keeping its input context server-fetched rather than client-asserted,
removes an entire class of "AI said I passed, so I should get credit"
disputes by construction.

## Consequences

- Any new Mentor mode that needs additional context (e.g. a future
  `explain_finding` mode, once the security scanner exists) must add a
  real query to `buildMentorContext()`, not accept the finding as a
  parameter from the client.
- `lib/mentor/prompt.ts` is a pure function specifically so its safety
  properties (system instructions before data, mode instructions present,
  no flag/secret leakage instructions) can be unit-tested without a live
  Anthropic API key or database — see
  `lib/mentor/__tests__/prompt.test.ts`.
- If a future feature needs the Mentor to trigger a real action (e.g.
  "regenerate my report"), that action must go through the same kind of
  authorization-checked, deterministic function the grading pipeline uses
  — never a free-form "the model decided to call this" path without a
  human-reviewable server-side check.
