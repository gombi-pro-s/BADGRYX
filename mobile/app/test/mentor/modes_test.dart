import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/mentor/modes.dart';

void main() {
  group('MentorModeApi', () {
    test('apiValue matches apps/web\'s MentorMode strings exactly', () {
      expect(MentorMode.explain.apiValue, 'explain');
      expect(MentorMode.hint.apiValue, 'hint');
      expect(MentorMode.teach.apiValue, 'teach');
      expect(MentorMode.analyzeFailure.apiValue, 'analyze_failure');
      expect(MentorMode.explainFinding.apiValue, 'explain_finding');
      expect(MentorMode.guideInvestigation.apiValue, 'guide_investigation');
      expect(MentorMode.reviewReport.apiValue, 'review_report');
      expect(MentorMode.reviewMethodology.apiValue, 'review_methodology');
    });

    test('every mode has a real, human-readable label', () {
      for (final mode in MentorMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.label, isNot(mode.apiValue));
      }
    });
  });

  group('defaultModeForContext', () {
    test('mirrors defaultModeForContext() in apps/web/src/lib/mentor/modes.ts', () {
      expect(defaultModeForContext('lab'), MentorMode.hint);
      expect(defaultModeForContext('ctf'), MentorMode.hint);
      expect(defaultModeForContext('investigation'), MentorMode.guideInvestigation);
      expect(defaultModeForContext('finding'), MentorMode.explainFinding);
      expect(defaultModeForContext('report'), MentorMode.reviewReport);
      expect(defaultModeForContext('general'), MentorMode.explain);
      expect(defaultModeForContext('skill'), MentorMode.explain);
      expect(defaultModeForContext('lesson'), MentorMode.explain);
    });
  });

  group('extraModesForContext', () {
    test('mirrors extraModesForContext() in apps/web/src/lib/mentor/modes.ts', () {
      expect(extraModesForContext('investigation'), [MentorMode.guideInvestigation]);
      expect(extraModesForContext('finding'), [MentorMode.explainFinding]);
      expect(extraModesForContext('report'), [MentorMode.reviewReport, MentorMode.reviewMethodology]);
      expect(extraModesForContext('lab'), <MentorMode>[]);
      expect(extraModesForContext('general'), <MentorMode>[]);
    });
  });

  group('modesForContext', () {
    test('general contexts offer only the four general modes', () {
      expect(modesForContext('general'), generalMentorModes);
    });

    test('a context with extras appends them after the general modes', () {
      expect(modesForContext('finding'), [...generalMentorModes, MentorMode.explainFinding]);
      expect(modesForContext('report'), [...generalMentorModes, MentorMode.reviewReport, MentorMode.reviewMethodology]);
    });
  });
}
