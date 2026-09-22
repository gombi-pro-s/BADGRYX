# ADR 0008: Security scanner findings are deterministic-engine-owned, with an explicit attack → fix → retest state machine

## Status

Accepted.

## Context

Section 8 of the spec requires the security scanning engine to be credible
and testable, explicitly warning against relying exclusively on an LLM to
produce findings: results must be groundable, reproducible, and not
hallucinated. It also describes a real remediation workflow — a finding is
discovered, triaged, fixed, and then retested to confirm the fix actually
worked — not a single boolean "resolved" flag. This mirrors the Skill
Graph's core lesson (ADR 0003): a claim ("this is fixed") is only real once
it is independently re-verified, not merely asserted.

## Decision

- **Findings are only ever created by the owning user's own session, for
  their own scan.** `scan_findings_insert_own` requires the parent `scans`
  row to belong to `auth.uid()`; there is no service-role-only or
  AI-only insert path. This keeps the door open for a future AI-enrichment
  phase to *add* explanation/triage text to a finding (`ai_enriched` flag)
  without ever letting an AI call be the sole origin of a finding's
  existence — the same non-fabrication principle as ADR 0007, applied to
  scan results instead of skill evidence.
- **All descriptive fields are set once, at insert time, by whichever rule
  matched** (`rule_id`, `category`, `severity`, `confidence`, `evidence`,
  `explanation`, `impact`, `remediation`, etc.) and are never edited after
  that — an "explanation" that could silently change after the fact would
  undermine trusting the record of what was actually found.
- **Only `scan_findings.status` changes after creation, and only through**
  **`public.transition_scan_finding_status()`**, a `SECURITY DEFINER`
  function that:
  1. Verifies the caller owns the parent scan, or is staff.
  2. Validates the transition against a fixed state graph (below) —
     illegal jumps (e.g. `discovered` straight to `verified_fixed`,
     skipping remediation and retest) are rejected.
  3. Writes an append-only `scan_finding_status_events` row (old status,
     new status, actor, optional note) — an inspectable history of the
     remediation journey, not just a mutable current-status column.
  4. Calls `log_audit_event()`.

  The state graph:

  | From | Legal next states |
  |---|---|
  | `discovered` | `remediation_required`, `false_positive`, `wont_fix` |
  | `remediation_required` | `fix_applied`, `false_positive`, `wont_fix` |
  | `fix_applied` | `retested`, `remediation_required` (retest not yet run, or reopened) |
  | `retested` | `verified_fixed`, `remediation_required` (retest showed it's still broken) |
  | `false_positive` / `wont_fix` / `verified_fixed` | `remediation_required` (reopen) |

  Re-asserting the current status is a no-op (idempotent), not an error and
  not a new history row.
- **`scan_files.size_bytes` is derived from the stored content via a CHECK
  constraint** (`size_bytes = octet_length(content)`), not trusted as a
  client-supplied number, and content is hard-capped at 300KB per file —
  keeping both storage and any future AI-enrichment prompt built from it
  bounded.
- **`scans.total_files` / `total_findings` / `findings_by_severity` are
  maintained by triggers**, not computed ad hoc by the UI or asserted by the
  client, so a scan's summary can never drift from its actual rows.

## Why

A scanner whose "fixed" status is just a client-settable boolean would let a
user (or a bug) mark a real vulnerability as resolved without ever proving
the fix worked — exactly the kind of self-reported claim the Skill Graph
was built to avoid making credible. Requiring a `retested` step before
`verified_fixed`, and recording every transition in an unforgeable history
table, makes "attack → fix → retest" a real, auditable workflow instead of
a single mutable label.

## Consequences

- The (not-yet-built) scanner UI must drive status changes through
  `transition_scan_finding_status()`, never a direct table update — RLS
  structurally prevents the latter anyway (no UPDATE policy on
  `scan_findings`).
- A future "rescan this file" flow that wants to auto-advance a finding to
  `retested`/`verified_fixed` must still go through this function (using
  the caller's own session, since it has no service-role bypass), so the
  same ownership and state-graph checks apply whether a human or the
  orchestration code triggers the transition.
- Any AI-enrichment phase added later may only update `explanation`-type
  context or set `ai_enriched = true` on a finding that already exists from
  the deterministic engine's insert — it must never gain its own path to
  insert a `scan_findings` row on a user's behalf that the user's own
  session didn't create, keeping "the AI cannot invent findings"
  structurally true rather than just prompted.
- `supabase/tests/007_scanner_rls.sql` is the executable spec for the state
  graph above; any change to the legal transitions must update that test,
  not just this document.
