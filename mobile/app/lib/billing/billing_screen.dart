import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import 'billing.dart';

/// Mirrors apps/web's settings/billing/page.tsx queries exactly.
Future<(BillingSubscription?, BillingPlan?, List<PlanEntitlement>)> fetchBilling(
  SupabaseClient client,
  String userId,
) async {
  final subscriptionRow = await client
      .from('subscriptions')
      .select('plan_id, status, provider, current_period_end')
      .eq('subject_type', 'user')
      .eq('subject_id', userId)
      .inFilter('status', ['trialing', 'active', 'past_due'])
      .maybeSingle();

  if (subscriptionRow == null) return (null, null, const <PlanEntitlement>[]);
  final subscription = BillingSubscription.fromRow(subscriptionRow);

  final planRow = await client
      .from('plans')
      .select('id, slug, name, description, price_cents, currency, interval')
      .eq('id', subscription.planId)
      .single();
  final plan = BillingPlan.fromRow(planRow);

  final entitlementRows = await client.from('plan_entitlements').select('key, value').eq('plan_id', plan.id);
  final entitlements = (entitlementRows as List)
      .map((row) => PlanEntitlement.fromRow(row as Map<String, dynamic>))
      .toList();

  return (subscription, plan, entitlements);
}

/// Shows the user's real plan, subscription status, and entitlements
/// (the same server-enforced get_entitlement() values apps/web's own
/// billing page shows), plus a real "Upgrade to Pro" flow: a Bearer-
/// authed POST to `/api/billing/checkout` (same provider calls as
/// settings/billing/actions.ts, see ADR 0047) returns the payment
/// provider's own hosted checkout URL, shown via a copy-link dialog --
/// the same pattern as the Organizations screen's invite link -- rather
/// than embedding a WebView, since this app never touches card details
/// either way. Canceling or otherwise managing an existing subscription
/// still happens on the web app -- named as a real, deliberate scope
/// boundary, not silently missing. See ADR 0037/0047.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  late Future<(BillingSubscription?, BillingPlan?, List<PlanEntitlement>)> _future;
  String? _checkingOutProvider;
  String? _checkoutError;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(BillingSubscription?, BillingPlan?, List<PlanEntitlement>)> _load() {
    final client = Supabase.instance.client;
    return fetchBilling(client, client.auth.currentUser!.id);
  }

  Future<void> _startCheckout(String provider) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      setState(() => _checkoutError = 'Your session has expired. Please log in again.');
      return;
    }
    setState(() {
      _checkingOutProvider = provider;
      _checkoutError = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${AppEnv.apiBaseUrl}/api/billing/checkout'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${session.accessToken}'},
        body: jsonEncode({'provider': provider}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(body['error'] as String? ?? 'Checkout failed (${response.statusCode}).');
      }
      if (mounted) await _showCheckoutLinkDialog(body['url'] as String);
    } catch (e) {
      setState(() => _checkoutError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _checkingOutProvider = null);
    }
  }

  Future<void> _showCheckoutLinkDialog(String url) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Checkout link ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Open this link in your browser to pay -- card details go straight to your payment "
              "provider's own secure page, never through this app. Your plan updates automatically once "
              'the payment is confirmed.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            SelectableText(url, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: url)), child: const Text('Copy')),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: RefreshIndicator(
        onRefresh: () async {
          final next = _load();
          setState(() => _future = next);
          await next;
        },
        child: FutureBuilder<(BillingSubscription?, BillingPlan?, List<PlanEntitlement>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  Padding(padding: const EdgeInsets.all(24), child: Text('Could not load billing: ${snapshot.error}')),
                ],
              );
            }
            final (subscription, plan, entitlements) = snapshot.data!;
            final isPro = isProPlan(plan?.slug);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(plan?.name ?? 'Free', style: Theme.of(context).textTheme.titleMedium),
                                if (subscription != null)
                                  Text(subscription.status, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                            if (isPro)
                              Chip(
                                label: const Text('Pro'),
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              ),
                          ],
                        ),
                        if (plan?.description != null) ...[
                          const SizedBox(height: 12),
                          Text(plan!.description!),
                        ],
                        if (entitlements.isNotEmpty) ...[
                          const Divider(height: 24),
                          ...entitlements.map(
                            (e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(formatEntitlementKey(e.key), style: Theme.of(context).textTheme.bodySmall),
                                  Text('${e.value}', style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (isPro) ...[
                  const SizedBox(height: 16),
                  Text(
                    "Manage or cancel your subscription from the web app's Settings -> Billing page.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text(
                    'Upgrade to Pro for more concurrent labs, a bigger daily AI Mentor allowance, cyber range '
                    'access, team management, and advanced reports. \$19/month.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (!AppEnv.isApiConfigured)
                    const Text(
                      "Checkout isn't configured on this build. Run with --dart-define=API_BASE_URL=... to "
                      'enable it. See mobile/app/README.md.',
                      style: TextStyle(fontSize: 12),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: checkoutProviderLabel.entries.map((entry) {
                        final provider = entry.key;
                        return FilledButton(
                          onPressed: _checkingOutProvider != null ? null : () => _startCheckout(provider),
                          child: Text(
                            _checkingOutProvider == provider ? 'Starting...' : 'Upgrade with ${entry.value}',
                          ),
                        );
                      }).toList(),
                    ),
                  if (_checkoutError != null) ...[
                    const SizedBox(height: 8),
                    Text(_checkoutError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
