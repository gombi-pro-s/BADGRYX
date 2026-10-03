class BillingSubscription {
  BillingSubscription({required this.planId, required this.status, required this.provider, this.currentPeriodEnd});

  final String planId;
  final String status; // 'trialing' | 'active' | 'past_due'
  final String provider; // 'stripe' | 'paystack' | 'flutterwave'
  final DateTime? currentPeriodEnd;

  factory BillingSubscription.fromRow(Map<String, dynamic> row) {
    return BillingSubscription(
      planId: row['plan_id'] as String,
      status: row['status'] as String,
      provider: row['provider'] as String,
      currentPeriodEnd: row['current_period_end'] != null ? DateTime.parse(row['current_period_end'] as String) : null,
    );
  }
}

class BillingPlan {
  BillingPlan({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    required this.priceCents,
    required this.currency,
    required this.interval,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;
  final int priceCents;
  final String currency;
  final String interval;

  factory BillingPlan.fromRow(Map<String, dynamic> row) {
    return BillingPlan(
      id: row['id'] as String,
      slug: row['slug'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      priceCents: row['price_cents'] as int,
      currency: row['currency'] as String,
      interval: row['interval'] as String,
    );
  }
}

class PlanEntitlement {
  PlanEntitlement({required this.key, required this.value});

  final String key;
  final dynamic value;

  factory PlanEntitlement.fromRow(Map<String, dynamic> row) {
    return PlanEntitlement(key: row['key'] as String, value: row['value']);
  }
}

/// Mirrors apps/web's settings/billing/page.tsx: `isPro = plan?.slug === "pro"`.
bool isProPlan(String? slug) => slug == 'pro';

/// Mirrors apps/web's settings/billing/page.tsx: `e.key.replace(/_/g, " ")`.
String formatEntitlementKey(String key) => key.replaceAll('_', ' ');

/// Mirrors settings/billing/page.tsx's three UpgradeButton labels (minus
/// the "Upgrade with " prefix, applied at the call site) -- the provider
/// ids `/api/billing/checkout` accepts (see ADR 0047).
const Map<String, String> checkoutProviderLabel = {'stripe': 'Stripe', 'paystack': 'Paystack', 'flutterwave': 'Flutterwave'};
