import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Read-only: shows the user's real plan, subscription status, and
/// entitlements (the same server-enforced get_entitlement() values
/// apps/web's own billing page shows) -- exactly what a mobile user
/// needs to know about their plan. Checkout itself is deliberately not
/// built here: it needs a payment provider's own hosted, secure checkout
/// page (Stripe/Paystack/Flutterwave), not something to reimplement or
/// embed in a WebView for a first mobile slice. Upgrading or managing a
/// subscription happens on the web app -- named as a real, deliberate
/// scope boundary, not silently missing. See ADR 0037.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  late Future<(BillingSubscription?, BillingPlan?, List<PlanEntitlement>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(BillingSubscription?, BillingPlan?, List<PlanEntitlement>)> _load() {
    final client = Supabase.instance.client;
    return fetchBilling(client, client.auth.currentUser!.id);
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
                const SizedBox(height: 16),
                Text(
                  isPro
                      ? "Manage or cancel your subscription from the web app's Settings -> Billing page."
                      : "Upgrade to Pro for more concurrent labs, a bigger daily AI Mentor allowance, cyber "
                            "range access, team management, and advanced reports. Upgrading happens on the web "
                            "app's Settings -> Billing page -- checkout runs through your payment provider's own "
                            'secure page, not in this app.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
