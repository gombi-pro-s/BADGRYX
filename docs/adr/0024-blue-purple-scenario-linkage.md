# ADR 0024: Blue/Purple Team scenario linkage

## Status

Accepted.

## Context

`RELEASE_CHECKLIST.md` had "Blue/Purple Team scenario linkage" as not
started. Investigations (the blue-team side — analyze evidence, answer
questions) and labs/CTF challenges (the red-team side — carry out an
attack) have existed as two entirely separate content types since ADR
0006/the investigation schema. Nothing connected them: a learner who did
a red-team lab had no way to discover a blue-team investigation covering
the same incident, and vice versa. "Purple Team" is exactly this pairing
— seeing both sides of one scenario, not two unrelated exercises.

## Decision

- Two plain junction tables, mirroring `capstone_labs`/`capstone_skills`
  exactly: `investigation_labs` (`investigation_id`, `lab_id`) and
  `investigation_ctf_challenges` (`investigation_id`, `challenge_id`).
  Publicly readable (the link itself isn't sensitive), staff-write only.
- Admin: `/admin/investigations/[investigationId]` gained a "Related
  attack scenario (Purple Team linkage)" section with two toggle-chip
  taggers (`ItemTagger`, a generalized version of the capstones admin's
  `LabTagger`/`SkillTagger` pattern, parameterized by save-button label
  since it now tags two different item kinds on the same page).
- Learner: `/investigate/[investigationId]` shows a "Purple Team" banner
  linking to the red-team lab(s)/CTF challenge(s) it's paired with; `/labs/
  [labId]` and `/ctf/[challengeId]` show the same banner in reverse,
  linking to the blue-team investigation(s) analyzing that exact attack.
- One real seeded pairing, not just schema: **Purple Team: Detecting the
  Database Lateral Movement** is the literal blue-team side of ADR 0023's
  "Cyber Range: Lateral Movement to the Database Host" lab — the same
  leaked cron credential, the same source/target hosts, an auth log
  showing the exact anomalous login a SOC analyst would need to catch, and
  questions requiring correlating the cron schedule against the log
  timestamp to recognize the off-schedule login as the intrusion.

## Why

A dedicated new content type (a "scenario" entity wrapping both a lab and
an investigation) would have been a bigger schema change for the same
outcome a simple cross-reference already delivers, and it's a pattern this
schema already trusts (`capstone_labs`/`capstone_skills`) rather than a
new one to review. The real seeded pairing is what makes this "linkage"
rather than "a table nothing populates" — the two pieces of content
genuinely describe the same incident from both sides, not thematically
similar but disconnected scenarios.

## Consequences

- 1 new SQL regression test file (`supabase/tests/025_blue_purple_scenario_
  linkage.sql`, 5 assertions): staff can link, a plain user cannot write a
  link but can read one, deleting a linked lab cascades the link, and —
  the one that actually proves this is a real pairing, not just RLS on an
  empty table — a direct query confirms the seeded investigation
  genuinely links to the seeded lab by their real slugs. 179 SQL
  assertions total (was 178).
- No new unit tests: this phase is UI wiring and content seeding, no new
  pure logic to test in isolation (the taggers are the same toggle-chip/
  save-transition shape as the existing, already-covered-by-manual-review
  `LabTagger`/`SkillTagger` pattern).
- No new e2e tests: this phase adds no new route and no new auth wall to
  cover — the linkage only ever appears inside already-e2e-covered
  authenticated pages (`/investigate/[id]`, `/labs/[id]`, `/ctf/[id]`,
  `/admin/investigations/[id]`).
- A real authenticated click-through (see the Purple Team banner render
  and click through from one side to the other) needs a provisioned
  Supabase project, the same limitation as every other UI phase this
  session.
