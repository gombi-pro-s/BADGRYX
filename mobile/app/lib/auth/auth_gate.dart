import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';
import 'mfa.dart';
import 'verify_mfa_screen.dart';

/// Reactively swaps between LoginScreen, VerifyMfaScreen, and HomeShell
/// based on the real Supabase Auth session -- no app-level "isLoggedIn"
/// flag to drift out of sync, the stream IS the source of truth.
///
/// This is also the one real MFA step-up enforcement point on mobile,
/// and the single place it needs to be: every screen this app shows
/// after sign-in goes through here first, the same way web's
/// `requireUser()` is the point every protected Server Component/Action
/// already funnels through (ADR 0015). `challengeAndVerify()` fires
/// `AuthChangeEvent.mfaChallengeVerified` on this same stream (confirmed
/// against the real `gotrue` package source), so completing the
/// challenge on `VerifyMfaScreen` makes this rebuild and swap to
/// `HomeShell` on its own -- no explicit navigation needed, the same
/// pattern `LoginScreen` itself already relies on. Like web's own
/// middleware/requireUser() redirects, this is a UX-level gate, not an
/// RLS-level one: a stolen aal1 JWT can still call any Postgrest/RPC
/// endpoint this app's own RLS already allows at aal1, on either
/// client. RLS remains the real boundary either way; see ADR 0068.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        final aal = Supabase.instance.client.auth.mfa.getAuthenticatorAssuranceLevel();
        if (needsMfaStepUp(aal)) return const VerifyMfaScreen();
        return const HomeShell();
      },
    );
  }
}
