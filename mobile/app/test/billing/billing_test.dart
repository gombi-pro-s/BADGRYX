import 'package:flutter_test/flutter_test.dart';
import 'package:icorepen/billing/billing.dart';

void main() {
  group('BillingSubscription.fromRow', () {
    test('parses a real subscriptions row shape', () {
      final subscription = BillingSubscription.fromRow({
        'plan_id': 'plan-1',
        'status': 'active',
        'provider': 'stripe',
        'current_period_end': '2026-02-01T00:00:00.000Z',
      });
      expect(subscription.planId, 'plan-1');
      expect(subscription.status, 'active');
      expect(subscription.provider, 'stripe');
      expect(subscription.currentPeriodEnd, isNotNull);
    });

    test('a null current_period_end parses as null', () {
      final subscription = BillingSubscription.fromRow({
        'plan_id': 'plan-1',
        'status': 'trialing',
        'provider': 'paystack',
        'current_period_end': null,
      });
      expect(subscription.currentPeriodEnd, isNull);
    });
  });

  test('BillingPlan.fromRow parses a real plans row shape', () {
    final plan = BillingPlan.fromRow({
      'id': 'plan-1',
      'slug': 'pro',
      'name': 'Pro',
      'description': 'More labs, more Mentor, cyber range access.',
      'price_cents': 1900,
      'currency': 'usd',
      'interval': 'month',
    });
    expect(plan.slug, 'pro');
    expect(plan.name, 'Pro');
    expect(plan.priceCents, 1900);
  });

  test('PlanEntitlement.fromRow parses a real plan_entitlements row shape', () {
    final entitlement = PlanEntitlement.fromRow({'key': 'max_concurrent_labs', 'value': 5});
    expect(entitlement.key, 'max_concurrent_labs');
    expect(entitlement.value, 5);
  });

  group('isProPlan', () {
    test('true for the pro slug', () {
      expect(isProPlan('pro'), isTrue);
    });

    test('false for any other slug', () {
      expect(isProPlan('free'), isFalse);
      expect(isProPlan('enterprise'), isFalse);
    });

    test('false when there is no plan at all', () {
      expect(isProPlan(null), isFalse);
    });
  });

  group('formatEntitlementKey', () {
    test('replaces underscores with spaces', () {
      expect(formatEntitlementKey('max_concurrent_labs'), 'max concurrent labs');
    });

    test('leaves a key with no underscores unchanged', () {
      expect(formatEntitlementKey('seats'), 'seats');
    });
  });

  test('checkoutProviderLabel covers exactly the three real payment providers', () {
    expect(checkoutProviderLabel.keys.toSet(), {'stripe', 'paystack', 'flutterwave'});
    for (final entry in checkoutProviderLabel.entries) {
      expect(entry.value, isNot(entry.key), reason: '${entry.key} label should not be the raw provider id');
    }
  });
}
