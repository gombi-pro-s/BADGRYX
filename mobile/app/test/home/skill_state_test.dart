import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/home/skill_state.dart';

void main() {
  test('every real skill_state enum value has a real label mapping', () {
    for (final state in allSkillStates) {
      final label = skillStateLabel(state);
      expect(label, isNot(equals(state)), reason: '$state fell through to the raw-value fallback');
    }
  });

  test('label text matches apps/web components/skill-state-badge.tsx exactly', () {
    expect(skillStateLabel('NOT_STARTED'), 'Not started');
    expect(skillStateLabel('LEARNING'), 'Learning');
    expect(skillStateLabel('PRACTICING'), 'Practicing');
    expect(skillStateLabel('ASSESSED'), 'Assessed');
    expect(skillStateLabel('DEMONSTRATED'), 'Demonstrated');
    expect(skillStateLabel('MASTERED'), 'Mastered');
    expect(skillStateLabel('NEEDS_REVIEW'), 'Needs review');
  });

  test('an unrecognized state falls back to the raw value rather than throwing', () {
    expect(skillStateLabel('SOMETHING_NEW'), 'SOMETHING_NEW');
  });
}
