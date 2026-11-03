import { describe, expect, it } from "vitest";

import { createNativeSubscriptions } from "../../../src/blocks/billing/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

describe("createNativeSubscriptions", () => {
  it("creates a subscription and reads its period", async () => {
    const { transport, call } = fakeTransport({
      create_native_subscription: {
        id: "s1",
        plan: "pro",
        currency: "EUR",
        unit_amount: "3000",
        quantity: 2,
        interval: "month",
        period_start: "2026-01-01T00:00:00Z",
        period_end: "2026-02-01T00:00:00Z",
      },
    });

    const subscription = await createNativeSubscriptions({ transport })
      .create({
        organizationId: "o1",
        plan: "pro",
        currency: "EUR",
        unitAmount: "3000",
        quantity: 2,
      })
      .orThrow();

    expect(subscription).toMatchObject({
      id: "s1",
      unitAmount: "3000",
      quantity: 2,
    });
    expect(call).toHaveBeenCalledWith(
      "better_supabase",
      "create_native_subscription",
      expect.objectContaining({ tenant: "o1", billing_interval: "month" }),
    );
  });

  it("returns the proration with its ledger transaction", async () => {
    const { transport, call } = fakeTransport({
      prorate_change: {
        subscription_id: "s1",
        credit: "3000",
        charge: "6000",
        net: "3000",
        currency: "EUR",
        transaction_id: "tx1",
      },
    });

    const proration = await createNativeSubscriptions({ transport })
      .prorateChange({
        subscriptionId: "s1",
        unitAmount: "6000",
        at: "2026-01-16T00:00:00Z",
      })
      .orThrow();

    expect(proration).toEqual({
      subscriptionId: "s1",
      credit: "3000",
      charge: "6000",
      net: "3000",
      currency: "EUR",
      transactionId: "tx1",
    });
    expect(call).toHaveBeenCalledWith("better_supabase", "prorate_change", {
      subscription_id: "s1",
      unit_amount: "6000",
      quantity: null,
      at: "2026-01-16T00:00:00Z",
    });
  });

  it("has no transaction for a change that nets to zero", async () => {
    const { transport } = fakeTransport({
      prorate_change: {
        subscription_id: "s1",
        credit: "0",
        charge: "0",
        net: "0",
        currency: "EUR",
        transaction_id: null,
      },
    });

    const proration = await createNativeSubscriptions({ transport })
      .prorateChange({ subscriptionId: "s1" })
      .orThrow();

    expect(proration.transactionId).toBeNull();
  });

  it("cancels a subscription", async () => {
    const { transport } = fakeTransport({ cancel_native_subscription: true });

    expect(
      await createNativeSubscriptions({ transport }).cancel("s1").orThrow(),
    ).toBe(true);
  });
});
