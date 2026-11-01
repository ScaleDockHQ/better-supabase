import "temporal-polyfill/global";
import { testShippingProvider } from "better-supabase/testing";
import { describe, expect, it } from "vitest";

import { createShippingProvider } from "../src/shipping-provider.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

/** A carrier that sells one service, remembers labels by idempotency key. */
function fakeCarrier() {
  const labels = new Map<string, { id: string; trackingNumber: string }>();
  const voided = new Set<string>();

  return fakeFetch(({ method, path, headers, body }) => {
    if (path === "/rates") {
      return {
        json: {
          rates: [{ service: "standard", amountMinor: "695", currency: "EUR" }],
        },
      };
    }

    if (path === "/labels" && method === "POST") {
      // SAFETY: this fake receives the label request the adapter posts.
      const { service } = body as { service: string };

      if (service !== "standard") {
        return { status: 422, json: { message: "unknown service" } };
      }

      const key = headers.get("idempotency-key") ?? crypto.randomUUID();

      const label = labels.get(key) ?? {
        id: `L-${labels.size + 1}`,
        trackingNumber: `T-${labels.size + 1}`,
      };

      labels.set(key, label);

      return {
        json: {
          id: label.id,
          trackingNumber: label.trackingNumber,
          costMinor: "695",
          currency: "EUR",
        },
      };
    }

    if (path.startsWith("/tracking/")) {
      const number = decodeURIComponent(path.slice("/tracking/".length));

      return [...labels.values()].some(
        (label) => label.trackingNumber === number,
      )
        ? {
            json: {
              events: [{ id: "e1", status: "created", at: 1_790_000_000_000 }],
            },
          }
        : { status: 404 };
    }

    const id = path.split("/")[2] ?? "";

    voided.add(id);

    return { json: {} };
  });
}

const address = {
  line1: "Dam 1",
  city: "Amsterdam",
  postalCode: "1012JS",
  country: "NL",
};

describe("shipping provider", () => {
  it("passes the better-supabase conformance kit", async () => {
    const carrier = createShippingProvider({
      ...OPTIONS,
      fetch: fakeCarrier().fetch,
    });

    await expect(
      testShippingProvider(carrier, {
        from: address,
        to: { ...address, city: "Utrecht" },
        service: "standard",
        currency: "EUR",
      }),
    ).resolves.toBeDefined();
  });

  it("refuses a shipment without packages as invalid_input", async () => {
    const carrier = createShippingProvider({
      ...OPTIONS,
      fetch: fakeCarrier().fetch,
    });

    const result = await carrier.rates({
      from: address,
      to: address,
      parcels: [],
    });

    expect(result.ok ? undefined : result.error.kind).toBe("invalid_input");
  });
});
