import type Stripe from "stripe";

import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { StripeSource } from "../../src/blocks/billing/index.ts";
import type {
  StripePaymentsOptions,
  StripeTaxOptions,
} from "../../src/commerce/index.ts";

import { stripeFromKey } from "../../src/stripe/index.ts";

const made = vi.hoisted((): unknown[] => []);

vi.mock("stripe", async (importOriginal) => {
  const { default: Actual } = await importOriginal<{
    default: typeof Stripe;
  }>();

  class Recording extends Actual {
    constructor(key: string, options?: Stripe.StripeConfig) {
      made.push([key, options]);
      super(key, options);
    }
  }

  return { default: Recording };
});

describe("stripeFromKey", () => {
  it("creates the client from the stripe package once, on first use", async () => {
    made.length = 0;

    const get = stripeFromKey({
      secretKey: "sk_test_123",
      apiVersion: "2026-09-30.clover",
    });

    expect(made).toEqual([]);

    const [first, second] = await Promise.all([get(), get()]);

    expect(second).toBe(first);
    expect(await get()).toBe(first);
    expect(typeof first.checkout.sessions.create).toBe("function");
    expect(made).toEqual([
      [
        "sk_test_123",
        { httpClient: expect.anything(), apiVersion: "2026-09-30.clover" },
      ],
    ]);
  });

  it("leaves the API version to the package when none is given", async () => {
    made.length = 0;

    await stripeFromKey({ secretKey: "sk_test_456" })();
    expect(made).toEqual([["sk_test_456", { httpClient: expect.anything() }]]);
  });

  it("is a stripe source for billing, usage and the commerce adapters", () => {
    expectTypeOf(stripeFromKey({ secretKey: "sk" })).toExtend<StripeSource>();

    const payments: StripePaymentsOptions["stripe"] = stripeFromKey({
      secretKey: "sk",
    });

    const tax: StripeTaxOptions["stripe"] = stripeFromKey({ secretKey: "sk" });

    expect(typeof payments).toBe("function");
    expect(typeof tax).toBe("function");
  });
});
