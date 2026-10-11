import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'validation.dart';

/// Mirrors `/login/verify-mfa`'s own `VerifyMfaForm`: a 6-digit code
/// from the user's authenticator app, checked against whichever
/// verified TOTP factor the session already has. `AuthGate` shows this
/// in place of `HomeShell` whenever `needsMfaStepUp()` is true, and
/// stops showing it the moment `challengeAndVerify()` succeeds (it
/// fires `AuthChangeEvent.mfaChallengeVerified` on the same stream
/// `AuthGate` already listens to -- no explicit navigation here).
///
/// Unlike the web page, this adds a "Log out instead" link. Web has no
/// such escape hatch, but a stuck browser tab still has an address bar
/// to type `/login` into; a mobile screen with no session and no
/// Navigator stack to pop has no equivalent, so a user without their
/// authenticator device (lost phone, reinstalled app) would otherwise
/// have no way out of this screen at all. This is a deliberate,
/// mobile-specific addition, not an unplanned feature -- signing out
/// changes nothing about the security model, it's the exact same
/// action the AppBar's logout button already performs. See ADR 0068.
class VerifyMfaScreen extends StatefulWidget {
  const VerifyMfaScreen({super.key});

  @override
  State<VerifyMfaScreen> createState() => _VerifyMfaScreenState();
}

class _VerifyMfaScreenState extends State<VerifyMfaScreen> {
  final _codeController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (!isValidTotpCode(code)) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final factors = await client.auth.mfa.listFactors();
      final factor = factors.totp.isEmpty ? null : factors.totp.first;
      if (factor == null) {
        // Nothing to verify against -- same "send them on rather than
        // trapping them" reasoning as verifyMfaChallengeAction(). The
        // next AuthGate rebuild (triggered by setState below) will see
        // nextLevel == currentLevel and show HomeShell.
        return;
      }
      await client.auth.mfa.challengeAndVerify(factorId: factor.id, code: code);
    } on AuthException {
      setState(() => _error = 'Invalid or expired code. Try again.');
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Verify your identity', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Enter the 6-digit code from your authenticator app.'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Authentication code'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(_submitting ? 'Verifying...' : 'Verify'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting ? null : () => Supabase.instance.client.auth.signOut(),
                    child: const Text('Log out instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
