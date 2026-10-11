import 'package:supabase_flutter/supabase_flutter.dart';

/// Direct port of `signInAction()`/`requireUser()`'s own check
/// (`aal.nextLevel === "aal2" && aal.currentLevel !== aal.nextLevel`,
/// see `lib/auth/session.ts` and ADR 0015): the session has a verified
/// MFA factor that its current level hasn't reached yet, so a step-up
/// challenge is owed before the app is any more "signed in" than that.
///
/// `AuthMFAGetAuthenticatorAssuranceLevelResponse` comes straight from
/// `Supabase.instance.client.auth.mfa.getAuthenticatorAssuranceLevel()`
/// (synchronous in the Dart SDK, unlike the JS SDK's async version --
/// verified against the real `gotrue` package source). See ADR 0068.
bool needsMfaStepUp(AuthMFAGetAuthenticatorAssuranceLevelResponse aal) {
  return aal.nextLevel == AuthenticatorAssuranceLevels.aal2 && aal.currentLevel != aal.nextLevel;
}
