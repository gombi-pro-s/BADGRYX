/// The general-chat subset of apps/web's lib/mentor/modes.ts
/// ALL_MENTOR_MODES/GENERAL_MODES/MODE_LABELS -- this first mobile Mentor
/// slice is scoped to `contextType: 'general'` only (no lab/lesson/finding
/// deep links from mobile yet), so only the four modes GENERAL_MODES
/// offers everywhere are ported.
enum MentorMode { explain, hint, teach, analyzeFailure }

extension MentorModeApi on MentorMode {
  /// The exact string the API's `mode` field expects (mirrors MentorMode
  /// in apps/web's types/database.ts).
  String get apiValue => switch (this) {
    MentorMode.explain => 'explain',
    MentorMode.hint => 'hint',
    MentorMode.teach => 'teach',
    MentorMode.analyzeFailure => 'analyze_failure',
  };

  String get label => switch (this) {
    MentorMode.explain => 'Explain',
    MentorMode.hint => 'Hint',
    MentorMode.teach => 'Teach',
    MentorMode.analyzeFailure => 'Analyze a failure',
  };
}
