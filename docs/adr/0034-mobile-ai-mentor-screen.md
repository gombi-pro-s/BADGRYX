# ADR 0034: AI Mentor chat screen in the Flutter mobile app

## Status

Accepted.

## Context

ADR 0033 built the backend half of this: `/api/mentor/chat` now accepts
an `Authorization: Bearer <token>` header from a non-browser client,
alongside apps/web's own cookie-session calls. This ADR is the mobile
half -- an actual chat screen the Flutter app's user can talk to.

Unlike every other mobile screen so far (Dashboard, Labs, Skills, CTF,
Investigate, Exams, Capstones), the Mentor doesn't talk to Supabase
directly: it calls a Next.js Route Handler that streams NDJSON
(`{type:"delta"}` per token, then one terminal `{type:"done"}`/
`{type:"error"}`), because the actual Anthropic call and prompt-injection
guardrails live server-side (see ADR 0020). That meant porting real
protocol-parsing logic to Dart, not just Postgrest/RPC calls, and adding
a second base URL the app needs to know about.

## Decision

- `lib/mentor/ndjson.dart`: a faithful port of apps/web's
  `lib/mentor/ndjson.ts` -- `parseNdjsonLines(buffer)` returns
  `(events, remainder)` with the exact same chunk-boundary-reassembly
  contract, and a `MentorStreamEvent` sealed class (`MentorDeltaEvent`/
  `MentorDoneEvent`/`MentorErrorEvent`) standing in for the TS
  discriminated union, matched with Dart 3 pattern-matching `switch`
  expressions at the call site.
- `lib/mentor/modes.dart`: only the four `GENERAL_MODES` from
  `lib/mentor/modes.ts` (`explain`/`hint`/`teach`/`analyze_failure`) --
  this first mobile slice is scoped to `contextType: 'general'` only, the
  same honest scope boundary as the terminal-backed labs' "not on mobile
  yet" banner. No lab/lesson/finding/report deep links from mobile yet.
- `config/env.dart`: a new `AppEnv.apiBaseUrl`
  (`String.fromEnvironment('API_BASE_URL')`) -- deliberately **optional**,
  unlike `SupabaseEnv` (which blocks the whole app via
  `ConfigMissingScreen`). A build with no `API_BASE_URL` still has a fully
  working app; only `MentorScreen` itself shows a plain "AI Mentor isn't
  configured on this build" message instead of crashing or faking a
  response.
- `lib/mentor/mentor_screen.dart`: the chat UI -- a mode-selector row of
  `ChoiceChip`s, a scrolling message list, and a text input. Sending a
  message does a real streamed `http.Client().send()` POST to
  `<apiBaseUrl>/api/mentor/chat` with `Authorization: Bearer
  <session.accessToken>` (the exact header `requireApiUser()` reads),
  decodes the response body incrementally via `parseNdjsonLines`, and
  updates the in-progress assistant bubble on every `delta` event so text
  visibly streams in rather than appearing all at once. The terminal
  `done` event's quota is shown in the app bar; a non-200 response (401
  from an expired session, 429 quota exceeded, 400 validation) is parsed
  for its `{error}` body and shown inline instead of a raw exception.
- `http` promoted from a transitive to an explicit `pubspec.yaml`
  dependency, since it's now called directly (no reasonable hand-rolled
  alternative for HTTP, the same reasoning that justified
  `supabase_flutter` itself).
- Wired into `MoreScreen`'s menu, alongside Investigate/Exams/Capstones.

## Why

- **Porting the actual parsing logic, not re-deriving it**, keeps the two
  clients' streaming behavior identical -- the same reason ADR 0033's
  bearer-auth design was verified against real SDK source rather than
  assumed.
- **General-only scope stated up front** rather than silently
  implemented as a subset: a future phase adding lab/investigation/
  finding-scoped mobile Mentor deep links has exactly the same shape as
  ADR 0032's Capstones (a real vertical slice, named as partial rather
  than implied complete).
- **`AppEnv.apiBaseUrl` optional, `SupabaseEnv` mandatory** mirrors the
  established distinction between the app's one required backend
  (Supabase, every other screen) and an optional integration (Turnstile/
  billing providers on web; here, the Mentor's own Next.js API) that
  degrades to a clear message rather than blocking anything else.

## Consequences

- +8 unit tests (`ndjson_test.dart`, mirroring `ndjson.test.ts`'s 7
  cases plus one for the Dart-specific unknown-event-type
  `FormatException`) -- 69 `flutter test`s total (was 61).
- `flutter analyze` stayed clean; `flutter build web` succeeds both with
  and without `--dart-define=API_BASE_URL=...`, proving the graceful-
  degradation path actually compiles, not just the happy path.
- `http` is now a direct dependency (was already present transitively via
  `supabase_flutter`, so `flutter pub get` needed no new download).
- No real device/click-through against a live Anthropic-backed
  deployment -- same "needs a provisioned environment this sandbox
  doesn't have" limitation as every other live-integration item in
  `RELEASE_CHECKLIST.md`.
