import type { BillingInterval } from "@/types/database";

/**
 * The one paid plan this build supports today. All three webhook handlers
 * hardcode this slug rather than mapping an incoming price/plan id to a
 * plan -- adding a second paid tier means resolving that mapping instead of
 * this constant, in each webhook handler.
 */
export const PRO_PLAN_SLUG = "pro";

/**
 * Providers don't always echo back a period end on the event that triggers
 * activation (e.g. Stripe's checkout.session.completed doesn't include the
 * subscription's current_period_end without an extra API call to expand
 * it). Computing it from the plan's billing interval is a documented
 * simplification, accurate to within the same billing cycle it represents.
 */
export function computePeriodEnd(interval: BillingInterval, from: Date = new Date()): Date {
  const end = new Date(from);
  if (interval === "year") {
    end.setUTCFullYear(end.getUTCFullYear() + 1);
  } else {
    // 'month' is the only other recurring interval this build issues
    // checkouts for; 'free'/'lifetime' subscriptions never call this.
    end.setUTCMonth(end.getUTCMonth() + 1);
  }
  return end;
}
