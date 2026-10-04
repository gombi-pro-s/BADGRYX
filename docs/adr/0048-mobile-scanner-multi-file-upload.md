# ADR 0048: Multi-file upload on the mobile Scanner's "New scan" screen

## Status

Accepted.

## Context

ADR 0036/0044/0045 had narrowed the mobile Scanner's gap down to just
multi-file upload, named each time as needing a file picker this app's
first slices deliberately didn't build. Reading `/api/scanner/scan`'s
`requestSchema` showed the server side was never the blocker: it already
accepts `targetType: "uploaded_files"` and up to 20 `{filename, content}`
entries -- exactly the same shape `pasted_snippet` sends, just more of
them. The only real gap was a way to pick real files on a phone, which
Flutter's SDK alone cannot do.

`file_picker` is the one new dependency this ADR adds (alongside `http`,
ADR 0033's exception) -- there is no reasonable hand-rolled alternative
to a native/browser file-selection dialog, and it is the standard,
actively-maintained package for exactly this.

## Decision

- `pubspec.yaml`: added `file_picker: ^8.1.7`.
- `lib/scanner/scan.dart` gained `ScanUploadFile` (filename + decoded text
  content) and the pure `buildScanRequestBody()`, which picks
  `targetType: "uploaded_files"` plus every picked file when one or more
  were picked, or `targetType: "pasted_snippet"` plus the single paste-box
  file otherwise -- the exact two-target-type shape the server already
  accepts.
- `lib/scanner/new_scan_screen.dart`: a "Choose files" button calls
  `FilePicker.platform.pickFiles(allowMultiple: true, withData: true)`
  (`withData` since Flutter Web has no filesystem path, only bytes),
  decodes each as UTF-8 text, and lists the picked files (filename +
  character count, each removable). The paste-box fields are hidden once
  files are picked, since the request is either-or server-side; `_submit`
  now calls `buildScanRequestBody()` instead of hand-assembling one
  hardcoded `pasted_snippet` request.

## Why

Keeping `buildScanRequestBody()` pure and separate from the picker call
itself means the "which target type, which files" decision is fully unit-
tested without needing a real `FilePicker` (file selection has no
meaningful unit-test story on its own -- it's a platform dialog).

## Consequences

- +4 `flutter test`s (`buildScanRequestBody`: pasted-snippet shape when no
  files are picked, uploaded-files shape with every file when files are
  picked, title included/omitted) -- 125 `flutter test`s total (was 121).
- `flutter analyze` stays clean; `flutter build web` succeeds both with
  and without `API_BASE_URL` (file picking itself needs neither, only
  submission does).
- Closes ADR 0036's last named Scanner gap. "Enrich with AI" (ADR 0045)
  and manual status transitions (ADR 0044) were already real; the Scanner
  screen now has no named gaps left.
