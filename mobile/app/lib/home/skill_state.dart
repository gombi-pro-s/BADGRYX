import 'package:flutter/material.dart';

/// Mirrors apps/web's components/skill-state-badge.tsx exactly -- same 7
/// states, same label text, same relative color meaning (accent for
/// assessed/demonstrated, success for mastered, danger for needs_review).
/// Pure, so the label mapping is unit-tested without any widget/backend.
const List<String> allSkillStates = [
  'NOT_STARTED',
  'LEARNING',
  'PRACTICING',
  'ASSESSED',
  'DEMONSTRATED',
  'MASTERED',
  'NEEDS_REVIEW',
];

String skillStateLabel(String state) {
  switch (state) {
    case 'NOT_STARTED':
      return 'Not started';
    case 'LEARNING':
      return 'Learning';
    case 'PRACTICING':
      return 'Practicing';
    case 'ASSESSED':
      return 'Assessed';
    case 'DEMONSTRATED':
      return 'Demonstrated';
    case 'MASTERED':
      return 'Mastered';
    case 'NEEDS_REVIEW':
      return 'Needs review';
    default:
      return state;
  }
}

Color skillStateColor(String state, ColorScheme scheme) {
  switch (state) {
    case 'LEARNING':
      return Colors.blueGrey;
    case 'PRACTICING':
      return Colors.amber.shade800;
    case 'ASSESSED':
    case 'DEMONSTRATED':
      return scheme.primary;
    case 'MASTERED':
      return Colors.green.shade700;
    case 'NEEDS_REVIEW':
      return Colors.red.shade700;
    case 'NOT_STARTED':
    default:
      return scheme.onSurfaceVariant;
  }
}
