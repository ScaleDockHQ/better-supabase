import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import * as v from "valibot";

import { BILLING_TAG } from "@/features/billing/billing-cache";
import { bsb } from "@/lib/supabase/server";

/** The columns of a Stripe Sync Engine invoice the screen shows. */
const InvoiceJson = v.looseObject({
  id: v.string(),
  number: v.optional(v.nullable(v.string())),
  status: v.optional(v.nullable(v.string())),
  currency: v.optional(v.nullable(v.string())),
  total: v.optional(v.nullable(v.number())),
  created: v.optional(v.nullable(v.number())),
  hosted_invoice_url: v.optional(v.nullable(v.string())),
});

const SubscriptionJson = v.looseObject({
  status: v.optional(v.nullable(v.string())),
  price: v.optional(v.nullable(v.string())),
  quantity: v.optional(v.nullable(v.number())),
});

export interface BillingAccountInvoice {
  readonly id: string;
  readonly number: string | null;
  readonly status: string | null;
  readonly currency: string | null;
  /** In minor units. */
  readonly total: number | null;
  /** Epoch milliseconds. */
  readonly createdAt: number | null;
  readonly url: string | null;
}

export interface BillingAccount {
  readonly customerId: string | null;
  readonly seats: number;
  readonly subscriptionStatus: string | null;
  readonly subscriptionPrice: string | null;
  readonly invoices: readonly BillingAccountInvoice[];
}

/**
 * The tenant's Stripe customer, seat count, subscription and latest invoices
 * from `billing.overview`. Without a Stripe customer the overview is empty.
 * Throws on a failed read, so the private cache never keeps an error.
 */
export async function getBillingAccount(): Promise<BillingAccount | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(BILLING_TAG);
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const overview = await db.billing
    .overview({ organizationId, invoiceLimit: 12 })
    .orThrow();

  const subscription = v.safeParse(SubscriptionJson, overview.subscription);

  return {
    customerId: overview.customerId,
    seats: overview.seats,
    subscriptionStatus: subscription.success
      ? (subscription.output.status ?? null)
      : null,
    subscriptionPrice: subscription.success
      ? (subscription.output.price ?? null)
      : null,
    invoices: overview.invoices.flatMap((raw) => {
      const parsed = v.safeParse(InvoiceJson, raw);

      return parsed.success
        ? [
            {
              id: parsed.output.id,
              number: parsed.output.number ?? null,
              status: parsed.output.status ?? null,
              currency: parsed.output.currency ?? null,
              total: parsed.output.total ?? null,
              createdAt:
                parsed.output.created === undefined ||
                parsed.output.created === null
                  ? null
                  : parsed.output.created * 1000,
              url: parsed.output.hosted_invoice_url ?? null,
            },
          ]
        : [];
    }),
  };
}
