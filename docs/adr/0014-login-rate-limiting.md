# ADR 0014: Application-layer login rate limiting

## Status

Accepted.

## Context

`signInAction()` called `supabase.auth.signInWithPassword()` with nothing
in front of it: any number of password guesses against any account, as
fast as a client could send them. `RELEASE_CHECKLIST.md` had flagged
"application-layer auth rate limiting / CAPTCHA on signup" as a known,
unaddressed gap since early in the project. This is a real, currently
exploitable weakness, not a theoretical one — GoTrue/Supabase project
settings can add their own platform-level throttling (see
`MANUAL_SETUP.md`), but that's operator configuration on infrastructure
this sandbox has no access to, not something the app itself enforces.

## Decision

Three `SECURITY DEFINER` functions
(`supabase/migrations/20260922000020_login_rate_limiting.sql`), keyed by
email:

- `check_login_rate_limit(email)` — called from `signInAction()` *before*
  `signInWithPassword()`. Returns `allowed` + `retry_after_seconds`,
  blocking once 5 failed attempts for that email have been recorded in
  the last 15 minutes.
- `record_failed_login_attempt(email)` — called after a failed
  `signInWithPassword()`.
- `clear_login_attempts(email)` — called after a successful one, so a
  legitimate login immediately resets the counter instead of waiting out
  the window.

Only failed attempts are ever stored, and a success deletes them, so the
table never grows from ordinary usage. `login_attempts` has RLS enabled
and forced with **zero policies** — nobody, including an authenticated
user checking their own email, can touch it directly; the three functions
above are the only access path, the same pattern as
`organization_invitations.token_hash`.

This is the one place in the schema that grants `EXECUTE` to the `anon`
Postgres role. Every other `SECURITY DEFINER` function in this app is
called by an already-authenticated caller and keys off `auth.uid()` for
authorization; a login attempt is by definition pre-session, so there is
no `auth.uid()` yet, and `anon` is the only role that exists at that
point. The caller supplies the email explicitly rather than the function
reading it from a session.

`signInAction()` fails **open**, not closed, if the rate-limit check
itself errors (e.g. the RPC call fails) — a broken rate limiter must never
become a way to lock every user out of the app entirely.

## Why

Email-keyed limiting (not IP-keyed) was a deliberate, honestly-documented
trade-off, not an oversight:

- No IP address source in this codebase is currently trustworthy across
  every deployment target (direct vs. behind a proxy/CDN), and inventing
  one to extract from `x-forwarded-for` without knowing the real
  deployment topology would be exactly the kind of speculative code this
  project avoids — better to ship a real, working defense for the
  most common threat (repeated guesses against one account) than a
  half-working one for a broader threat model.
- This does mean an attacker who already knows a victim's email can force
  that account into a lockout by deliberately failing its password 5
  times — a known, standard trade-off of email-keyed rate limiting. The
  window is short (15 minutes) specifically to bound that cost: this is a
  brute-force/credential-stuffing defense, not a lockout-as-punishment
  feature, and a real attacker gains nothing from the lockout itself
  (they still don't have the password).

## Consequences

- `supabase/tests/020_login_rate_limiting.sql` proves: the `anon` role can
  call all three functions (the only role that exists pre-login); a fresh
  email is allowed; 5 recorded failures block a 6th with a positive
  `retry_after_seconds`; a different email is completely unaffected;
  `clear_login_attempts()` immediately un-blocks; and attempts older than
  the 15-minute window no longer count.
- The login form now shows "Too many failed attempts. Try again in N
  minutes." instead of the generic invalid-credentials message once
  blocked — this one message necessarily differs from the "never reveal
  whether the email exists" generic message, but it reveals nothing about
  account existence either (it fires identically whether or not the email
  is registered, since attempts are recorded regardless).
- Signup still has no CAPTCHA/rate limiting of its own — left as a
  separate, still-open item in `RELEASE_CHECKLIST.md` rather than folded
  in here, since it's a different attack (account creation abuse, not
  credential guessing) with a different fix shape.
