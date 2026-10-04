/// Mirrors apps/web's `lib/mentor/modes.ts` -- every `MentorMode` a mobile
/// deep link can reach, not just `GENERAL_MODES`. Originally this enum
/// only had the four general modes (no lab/lesson/finding/investigation/
/// report deep links from mobile yet); ADR 0059 added the rest once this
/// app started giving each context screen its own "Ask Mentor" entry
/// point, mirroring `defaultModeForContext()`/`extraModesForContext()`
/// exactly rather than hand-picking a subset.
enum MentorMode {
  explain,
  hint,
  teach,
  analyzeFailure,
  explainFinding,
  guideInvestigation,
  reviewReport,
  reviewMethodology,
}

extension MentorModeApi on MentorMode {
  /// The exact string the API's `mode` field expects (mirrors MentorMode
  /// in apps/web's types/database.ts).
  String get apiValue => switch (this) {
    MentorMode.explain => 'explain',
    MentorMode.hint => 'hint',
    MentorMode.teach => 'teach',
    MentorMode.analyzeFailure => 'analyze_failure',
    MentorMode.explainFinding => 'explain_finding',
    MentorMode.guideInvestigation => 'guide_investigation',
    MentorMode.reviewReport => 'review_report',
    MentorMode.reviewMethodology => 'review_methodology',
  };

  String get label => switch (this) {
    MentorMode.explain => 'Explain',
    MentorMode.hint => 'Hint',
    MentorMode.teach => 'Teach',
    MentorMode.analyzeFailure => 'Analyze a failure',
    MentorMode.explainFinding => 'Explain finding',
    MentorMode.guideInvestigation => 'Guide investigation',
    MentorMode.reviewReport => 'Review report',
    MentorMode.reviewMethodology => 'Review methodology',
  };
}

/// Mirrors `GENERAL_MODES` -- always offered, regardless of context.
const List<MentorMode> generalMentorModes = [
  MentorMode.explain,
  MentorMode.hint,
  MentorMode.teach,
  MentorMode.analyzeFailure,
];

/// Mirrors `defaultModeForContext()`: the mode a deep link into Mentor
/// should default to for a given context. `contextType` is a plain
/// string (`'lab'`, `'ctf'`, `'investigation'`, `'finding'`, `'report'`,
/// `'general'`, ...) mirroring `MentorContextType` the same way this
/// app's other screens use plain strings for database enums (e.g.
/// `reports/report.dart`'s `kind`) rather than a parallel Dart enum.
/// `'report'` defaults to `review_report`; the Reports screen itself
/// overrides to `review_methodology` for that kind, same as the web
/// page's own `mentorMode` computation.
MentorMode defaultModeForContext(String contextType) {
  switch (contextType) {
    case 'lab':
    case 'ctf':
      return MentorMode.hint;
    case 'investigation':
      return MentorMode.guideInvestigation;
    case 'finding':
      return MentorMode.explainFinding;
    case 'report':
      return MentorMode.reviewReport;
    default:
      return MentorMode.explain;
  }
}

/// Mirrors `extraModesForContext()`: extra mode pills to offer alongside
/// `generalMentorModes` for a given context.
List<MentorMode> extraModesForContext(String contextType) {
  switch (contextType) {
    case 'investigation':
      return [MentorMode.guideInvestigation];
    case 'finding':
      return [MentorMode.explainFinding];
    case 'report':
      return [MentorMode.reviewReport, MentorMode.reviewMethodology];
    default:
      return const [];
  }
}

/// The full set of mode pills `MentorScreen` shows for a given context --
/// general modes first, then that context's own extras, mirroring how
/// `mentor-chat.tsx` renders `[...GENERAL_MODES, ...extraModesForContext(contextType)]`.
List<MentorMode> modesForContext(String contextType) => [
  ...generalMentorModes,
  ...extraModesForContext(contextType),
];
