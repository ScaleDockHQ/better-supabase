import { describe, expect, it } from "vitest";

import type {
  BlockTransport,
  StripeClient,
} from "../../../src/blocks/billing/index.ts";

import { createBilling } from "../../../src/blocks/billing/index.ts";

const refuse = async (): Promise<never> => {
  throw new Error("stripe down");
};

/** A Stripe client whose every call fails, so each method's error path runs. */
const stripe = new Proxy(
  {},
  { get: () => new Proxy({}, { get: () => refuse }) },
  // SAFETY: the proxy answers every resource and method with a failing call.
) as unknown as StripeClient;

const transport: BlockTransport = {
  async call(_schema, fn) {
    switch (fn) {
      case "billing_customer": {
        return "cus_1";
      }

      case "billing_subscription_item": {
        return {
          subscription: "sub_1",
          item: "si_1",
          price: "p",
          quantity: 1,
          status: "active",
        };
      }

      case "billing_seat_count": {
        return 3;
      }

      default: {
        return null;
      }
    }
  },
};

describe("billing when Stripe fails", () => {
  const billing = createBilling({ transport, stripe });

  it("returns the failure from every Stripe-backed method", async () => {
    const results = await Promise.all([
      billing.changePlan({ organizationId: "o", change: { price: "p2" } }),
      billing.cancelAtPeriodEnd({ organizationId: "o", cancel: true }),
      billing.voidInvoice({ organizationId: "o", invoiceId: "in_1" }),
      billing.markInvoiceUncollectible({
        organizationId: "o",
        invoiceId: "in_1",
      }),
      billing.taxIds({ organizationId: "o" }),
      billing.addTaxId({
        organizationId: "o",
        taxId: { type: "eu_vat", value: "NL1" },
      }),
      billing.removeTaxId({ organizationId: "o", taxId: "txi_1" }),
      billing.updateCustomer({
        organizationId: "o",
        update: { email: "a@b.test" },
      }),
      billing.checkout({
        organizationId: "o",
        options: {
          price: "p",
          mode: "subscription",
          quantity: "seats",
          successUrl: "https://a/ok",
          cancelUrl: "https://a/no",
        },
      }),
      billing.startTrial({
        organizationId: "o",
        options: {
          price: "p",
          days: 7,
          params: { subscription_data: { metadata: { a: "b" } } },
          successUrl: "https://a/ok",
          cancelUrl: "https://a/no",
        },
      }),
      billing.portal({
        organizationId: "o",
        options: { returnUrl: "https://a" },
      }),
    ]);

    for (const result of results) {
      expect(result.ok).toBe(false);
    }
  });
});
