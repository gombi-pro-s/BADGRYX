import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/auth/mfa.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AuthMFAGetAuthenticatorAssuranceLevelResponse _aal({
  AuthenticatorAssuranceLevels? currentLevel,
  AuthenticatorAssuranceLevels? nextLevel,
}) {
  return AuthMFAGetAuthenticatorAssuranceLevelResponse(
    currentLevel: currentLevel,
    nextLevel: nextLevel,
    currentAuthenticationMethods: const [],
  );
}

void main() {
  group('needsMfaStepUp', () {
    test('true when the session is aal1 but a verified factor requires aal2', () {
      final aal = _aal(
        currentLevel: AuthenticatorAssuranceLevels.aal1,
        nextLevel: AuthenticatorAssuranceLevels.aal2,
      );
      expect(needsMfaStepUp(aal), isTrue);
    });

    test('false once the session has already reached aal2', () {
      final aal = _aal(
        currentLevel: AuthenticatorAssuranceLevels.aal2,
        nextLevel: AuthenticatorAssuranceLevels.aal2,
      );
      expect(needsMfaStepUp(aal), isFalse);
    });

    test('false when no verified factor exists at all (nextLevel stays aal1)', () {
      final aal = _aal(
        currentLevel: AuthenticatorAssuranceLevels.aal1,
        nextLevel: AuthenticatorAssuranceLevels.aal1,
      );
      expect(needsMfaStepUp(aal), isFalse);
    });

    test('false when there is no session at all (both levels null)', () {
      final aal = _aal();
      expect(needsMfaStepUp(aal), isFalse);
    });
  });
}
