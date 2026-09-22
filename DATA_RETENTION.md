# Data Retention Policy

This document describes exactly what iCorePen stores, for how long, and what
happens to it when an account is deleted — grounded in the real schema, not
aspirational. Every claim below is backed by a specific migration, trigger,
or SQL regression test cited inline; nothing here describes a control that
doesn't actually exist in the codebase.

If a category isn't listed, iCorePen doesn't collect it.

## The two-category model

Every table that references a user or organization falls into one of two
categories (see `docs/adr/0012-account-deletion.md` for the full reasoning):

- **Owned data** — the row's entire reason to exist is that user or
  organization. Deleting the account deletes the row (`ON DELETE CASCADE`).
  Examples: your profile, skill states, lab/quiz/CTF/investigation/capstone
  submissions, scanner scans and findings, Mentor conversations, your own
  organization memberships.
- **Attribution** — the row is a record of something a user *did*, and
  exists independently of them (an audit trail, another user's content,
  another organization's history). Deleting the account nulls out the
  "who did this" column (`ON DELETE SET NULL`) rather than deleting or
  blocking deletion of the historical record. Examples: `audit_log.actor_id`,
  a role grant's `granted_by`, an organization's `created_by`, a capstone
  review's `reviewer_id`.

## What's retained, and for how long

| Category | Examples | Retention | On account deletion |
|---|---|---|---|
| Profile & identity | `profiles`, `user_roles` | Until deletion | Deleted (CASCADE) |
| Skill Graph | `user_skill_states`, `skill_evidence` | Until deletion | Deleted (CASCADE) |
| Learning activity | lesson progress, quiz attempts, lab instances/progress, CTF submissions, investigation instances/submissions, capstone submissions | Until deletion | Deleted (CASCADE) |
| Security scanner | `scans`, `scan_files` (source you pasted/uploaded, size-bounded — see `SECURITY_AUDIT.md`), `scan_findings` | Until deletion | Deleted (CASCADE) |
| AI Mentor conversations | `mentor_conversations`, `mentor_messages` | Until deletion | Deleted (CASCADE) |
| Organization memberships | your own `organization_members` row | Until deletion or you leave | Deleted (CASCADE) |
| Subscriptions | `subscriptions` (your own, or an organization's) | Until deletion | Deleted — a dedicated `AFTER DELETE` trigger on `auth.users`/`organizations` cleans these up, since `subject_id` is polymorphic and can't carry a normal foreign key; see `SECURITY_AUDIT.md` AUDIT-010 |
| Audit log | `audit_log` | **Indefinite** | Row survives; `actor_id` is set to `NULL`. The entire point of an audit trail is that it outlives the actor — a deleted admin's role grants, capstone reviews, and org creation shouldn't vanish from history just because they later deleted their own account |
| Content you authored (as staff) | learning paths, labs, CTF challenges, investigations, capstones you created/reviewed | **Indefinite** — it's platform content other learners are actively using, not your personal data | Row survives; `created_by`/`reviewer_id` set to `NULL` |
| Failed login attempts | `login_attempts` | 15 minutes, or until your next successful login (whichever is first) | Not tied to a user id at all — keyed by email string only, so account deletion has nothing to clean up; see `docs/adr/0014-login-rate-limiting.md` |
| Billing webhook log | `billing_webhook_events` | **Indefinite** (system-level replay-protection/audit log, not user-scoped) | Not affected by account deletion — this table has no `user_id`/`subject_id` column at all. **Known limitation**: the raw `payload` column stores whatever the payment provider's webhook body contained, which for Stripe/Paystack/Flutterwave can include the customer's email and provider-side customer id (never a full card number — see the table's own comment in `20260921000011_entitlements.sql`). This is standard practice for payment-processor webhook logs (providers themselves retain the same data on their side, often longer, for their own compliance obligations) but is called out here rather than left undocumented |

## What's never retained at all

- **Passwords**: hashed by Supabase Auth (bcrypt), never touched by
  application code.
- **Lab/CTF flags and investigation exact-text answers**: stored only as a
  server-side hash (see `docs/adr/0002-rbac-model.md`'s sibling security
  docs and the admin CMS code) — the plaintext answer is never persisted
  anywhere, retention or otherwise.
- **Locked lab hints**: the AI Mentor's context builder only ever reads
  hints a specific user has already unlocked for their own lab instance —
  a locked hint's content is structurally never queried, let alone stored
  or sent anywhere, on that user's behalf.
- **Card numbers**: billing integrations use Stripe/Paystack/Flutterwave's
  hosted checkout — full card numbers never reach this application's
  servers or database at all.

## How to exercise your own retention rights

- **Export everything currently retained about you**: `GET
  /api/account/export` (linked from `/settings/privacy`) — every query
  explicitly scoped to your own id, not just "everything your session's
  RLS happens to permit." See `docs/adr/0012-account-deletion.md`.
- **Delete your account**: `/settings/privacy` → type your email to
  confirm. This is real and immediate — it calls the Supabase Auth Admin
  API to actually delete the account, not a soft "deactivate" flag. Proven
  end-to-end by `supabase/tests/018_account_deletion.sql` and
  `supabase/tests/021_subscription_cleanup_on_delete.sql`.

## Backups

Not yet configured — there is no real, provisioned Supabase project behind
this build (see `MANUAL_SETUP.md` §2), so there is no backup retention
schedule to document honestly yet. Once a real project is provisioned,
Supabase's own point-in-time-recovery/backup retention (configured in the
Supabase dashboard, not by this application's code) will apply and should
be documented here with its actual retention window.

## Third parties data is shared with

Only the providers you (or the operator) actually configure — this
application never shares data with a third party beyond what's needed to
provide the specific feature:

- **Anthropic** (AI Security Mentor, scanner AI enrichment): receives only
  the specific context described in `docs/adr/0007-ai-mentor-grounding.md`
  — your Skill Graph state, recent evidence, and the focus item you're
  asking about. Never your password, never another user's data.
- **Stripe / Paystack / Flutterwave** (only if configured — see
  `MANUAL_SETUP.md` §4): receives what's needed to process payment —
  email, plan selection — through each provider's own hosted checkout.
- **Cloudflare Turnstile** (only if configured — see `MANUAL_SETUP.md`
  §8): receives whatever Cloudflare's own widget collects to verify a
  signup isn't automated; this application never sees or stores that data
  itself, only Cloudflare's success/failure verdict.
