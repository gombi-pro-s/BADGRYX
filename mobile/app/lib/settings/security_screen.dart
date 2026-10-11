import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/validation.dart';

/// Mirrors `/settings/security`'s own two-factor authentication section
/// exactly: list verified TOTP factors with a two-step "Remove"
/// confirm, and an "Add authenticator app" flow that starts enrollment
/// (`enroll(factorType: FactorType.totp)`, after cleaning up any
/// previously abandoned unverified factor -- the same
/// `enrollTotpFactorAction` reasoning), shows the TOTP secret, and
/// verifies a 6-digit code (`challengeAndVerify()`) to activate it.
///
/// Shows the secret as a manual-entry code only, never the QR image:
/// `enroll()`'s `qr_code` is an SVG data URI (confirmed against the
/// real `gotrue` package source), and Flutter's own `Image` widget
/// can't render SVG without a new rendering dependency. The plain-text
/// `secret` is an officially documented fallback for exactly this case
/// ("in case they are unable to scan the QR code"), not a workaround --
/// web's own form already shows it alongside the QR image for the same
/// reason. See ADR 0068.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  late Future<List<Factor>> _future;

  bool _enrolling = false;
  String? _enrollFactorId;
  String? _enrollSecret;
  final _codeController = TextEditingController();
  bool _verifying = false;
  String? _enrollError;

  @override
  void initState() {
    super.initState();
    _future = _loadFactors();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<List<Factor>> _loadFactors() async {
    final result = await Supabase.instance.client.auth.mfa.listFactors();
    return result.totp;
  }

  Future<void> _refresh() async {
    final next = _loadFactors();
    setState(() => _future = next);
    await next;
  }

  Future<void> _logAudit(String action, {Map<String, dynamic>? metadata}) {
    return Supabase.instance.client.rpc(
      'log_audit_event',
      params: {
        'p_action': action,
        'p_target_type': 'user',
        'p_target_id': Supabase.instance.client.auth.currentUser!.id,
        'p_metadata': ?metadata,
      },
    );
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _enrolling = true;
      _enrollError = null;
    });
    try {
      final client = Supabase.instance.client;
      final existing = await client.auth.mfa.listFactors();
      final abandoned = existing.all.where((f) => f.factorType == FactorType.totp && f.status == FactorStatus.unverified);
      for (final factor in abandoned) {
        await client.auth.mfa.unenroll(factor.id);
      }

      final enrolled = await client.auth.mfa.enroll(factorType: FactorType.totp);
      await _logAudit('mfa.enrollment_started');
      setState(() {
        _enrollFactorId = enrolled.id;
        _enrollSecret = enrolled.totp?.secret;
      });
    } catch (e) {
      setState(() {
        _enrolling = false;
        _enrollError = 'Could not start enrollment.';
      });
    }
  }

  void _cancelEnrollment() {
    setState(() {
      _enrolling = false;
      _enrollFactorId = null;
      _enrollSecret = null;
      _enrollError = null;
      _codeController.clear();
    });
  }

  Future<void> _verifyEnrollment() async {
    final code = _codeController.text.trim();
    if (!isValidTotpCode(code)) {
      setState(() => _enrollError = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _verifying = true;
      _enrollError = null;
    });
    try {
      await Supabase.instance.client.auth.mfa.challengeAndVerify(factorId: _enrollFactorId!, code: code);
      await _logAudit('mfa.enrollment_completed');
      _cancelEnrollment();
      await _refresh();
    } catch (e) {
      setState(() => _enrollError = 'Invalid or expired code. Try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _removeFactor(String factorId) async {
    try {
      await Supabase.instance.client.auth.mfa.unenroll(factorId);
      await _logAudit('mfa.factor_removed', metadata: {'factor_id': factorId});
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove this device.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Two-factor authentication', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'Add an authenticator app (Google Authenticator, 1Password, Authy, etc.) as a second factor. '
            'Once enabled, logging in requires both your password and a 6-digit code from the app.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Factor>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              final factors = snapshot.data ?? const [];
              if (factors.isEmpty) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: factors
                      .map((factor) => _FactorTile(factor: factor, onRemove: () => _removeFactor(factor.id)))
                      .toList(),
                ),
              );
            },
          ),
          if (!_enrolling)
            OutlinedButton(onPressed: _startEnrollment, child: const Text('Add authenticator app'))
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _enrollFactorId == null
                  ? const Center(child: Padding(padding: EdgeInsets.all(8), child: Text('Setting up...')))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Open your authenticator app and add an account manually using this code, then enter "
                          "the 6-digit code it shows.",
                          style: TextStyle(fontSize: 12),
                        ),
                        if (_enrollSecret != null) ...[
                          const SizedBox(height: 8),
                          SelectableText(_enrollSecret!, style: const TextStyle(fontFamily: 'monospace')),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(labelText: '6-digit code'),
                        ),
                        if (_enrollError != null) ...[
                          const SizedBox(height: 8),
                          Text(_enrollError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: _verifying ? null : _verifyEnrollment,
                              child: Text(_verifying ? 'Verifying...' : 'Verify & enable'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(onPressed: _verifying ? null : _cancelEnrollment, child: const Text('Cancel')),
                          ],
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _FactorTile extends StatefulWidget {
  const _FactorTile({required this.factor, required this.onRemove});

  final Factor factor;
  final VoidCallback onRemove;

  @override
  State<_FactorTile> createState() => _FactorTileState();
}

class _FactorTileState extends State<_FactorTile> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.factor.friendlyName ?? 'Authenticator app'),
      subtitle: Text('Added ${widget.factor.createdAt.toLocal().toString().split(' ').first}'),
      trailing: _confirming
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: widget.onRemove,
                  child: Text('Yes', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                TextButton(onPressed: () => setState(() => _confirming = false), child: const Text('Cancel')),
              ],
            )
          : TextButton(
              onPressed: () => setState(() => _confirming = true),
              child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
    );
  }
}
