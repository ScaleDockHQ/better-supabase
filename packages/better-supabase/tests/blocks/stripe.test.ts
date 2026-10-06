import { describe, expect, it } from "vitest";

import {
  lazyStripe,
  type StripeClient,
  stripeClient,
} from "../../src/blocks/stripe.ts";

const client = { customers: {} } as unknown as StripeClient;

describe("stripeClient", () => {
  it("returns a client it is given", async () => {
    expect(await stripeClient(client)).toBe(client);
  });

  it("creates one from the stripe package with the fetch HTTP client", async () => {
    const made: unknown[] = [];
    class Stripe {
      constructor(key: string, options: unknown) {
        made.push([key, options]);
      }
      static createFetchHttpClient() {
        return "fetch";
      }
    }
    const created = await stripeClient(
      { secretKey: "sk_test", apiVersion: "2026-09-30" },
      () => Promise.resolve({ default: Stripe }),
    );
    expect(created).toBeInstanceOf(Stripe);
    expect(made).toEqual([
      ["sk_test", { httpClient: "fetch", apiVersion: "2026-09-30" }],
    ]);
    await stripeClient({ secretKey: "sk_2" }, () =>
      Promise.resolve({ default: Stripe }),
    );
    expect(made[1]).toEqual(["sk_2", { httpClient: "fetch" }]);
  });

  it("explains how to install it when it is missing", async () => {
    await expect(
      stripeClient({ secretKey: "sk" }, () => Promise.resolve(undefined)),
    ).rejects.toThrow(/pnpm add stripe/);
  });

  it("loads the real package lazily, once", async () => {
    const get = lazyStripe({ secretKey: "sk_test_123" });
    const first = await get();
    expect(await get()).toBe(first);
    expect(typeof first.checkout.sessions.create).toBe("function");
  });
});
