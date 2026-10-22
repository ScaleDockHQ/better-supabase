import { describe, expect, it } from "vitest";

import type { ShippingProvider } from "../../../src/blocks/shipments/index.ts";

import {
  flatRateCarrier,
  invalidShipmentRequest,
  shipmentCarrierOf,
  trackingUpdatesOf,
} from "../../../src/blocks/shipments/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { signWebhook } from "../../../src/core/signatures.ts";
import {
  ConformanceError,
  testShippingProvider,
} from "../../../src/testing/index.ts";

const SECRET = "whsec_Y2Fycmllci10ZXN0LXNlY3JldA==";
const FROM = { line1: "Dock 4", city: "Rotterdam", country: "NL" };
const TO = { line1: "Main St 1", city: "Berlin", country: "DE" };
const AT = "2026-10-22T08:00:00Z";

const services = {
  standard: { amount: money(495, "EUR"), additional: money(200, "EUR") },
  express: { amount: money(1500, "EUR"), estimatedDays: 1 },
};

const request = {
  from: FROM,
  to: TO,
  parcels: [{ weightGrams: 1000 }, { weightGrams: 500, lengthMm: 10 }],
};

describe("flatRateCarrier", () => {
  it("passes the ShippingProvider conformance kit", async () => {
    const carrier = flatRateCarrier({ services, webhookSecret: SECRET });

    const body = JSON.stringify({
      trackingNumber: "FR1",
      events: [{ id: "a", status: "in_transit", occurredAt: AT }],
    });

    const report = await testShippingProvider(carrier, {
      from: FROM,
      to: TO,
      service: "standard",
      currency: "EUR",
      webhook: {
        valid: async () => ({
          headers: await signWebhook(SECRET, { id: "m1", body }),
          body,
        }),
        forged: async () => ({
          headers: await signWebhook("whsec_d3Jvbmc=", { id: "m2", body }),
          body,
        }),
      },
    });

    expect(report.checks.filter((check) => !check.ok)).toEqual([]);
  });

  it("passes the kit without webhooks", async () => {
    const report = await testShippingProvider(flatRateCarrier({ services }), {
      from: FROM,
      to: TO,
      service: "express",
    });

    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("reports a carrier that breaks the contract", async () => {
    const good = flatRateCarrier({ services });

    const broken: ShippingProvider = {
      ...good,
      rates: () => AsyncResult.ok([]),
      createLabel: (label, options) =>
        good
          .createLabel(label, options)
          .map((found) => ({ ...found, labelId: crypto.randomUUID() })),
    };

    const error = await testShippingProvider(broken, {
      from: FROM,
      to: TO,
      service: "standard",
      webhook: {
        valid: () => ({ headers: {}, body: "{}" }),
        forged: () => ({ headers: {}, body: "{}" }),
      },
    }).catch((error_: unknown) => error_);

    if (!(error instanceof ConformanceError)) {
      throw new TypeError("expected a ConformanceError");
    }

    const failed = error.report.checks
      .filter((check) => !check.ok)
      .map((check) => check.name);

    expect(failed).toEqual(
      expect.arrayContaining([
        "refuses a request without packages or with a bad country",
        "quotes the service in the asked currency",
        "returns the same label for the same idempotency key",
        "reads signed tracking webhooks and refuses forged ones",
      ]),
    );
  });

  it("charges each further package the additional amount", async () => {
    const carrier = flatRateCarrier({ services });
    const rates = await carrier.rates(request).orThrow();

    expect(rates).toEqual([
      { carrier: "flat-rate", service: "standard", amount: money(695, "EUR") },
      {
        carrier: "flat-rate",
        service: "express",
        amount: money(3000, "EUR"),
        estimatedDays: 1,
      },
    ]);
    expect(
      await carrier.rates({ ...request, currency: "USD" }).orThrow(),
    ).toEqual([]);
  });

  it("returns the first label for a repeated idempotency key", async () => {
    const carrier = flatRateCarrier({ services, trackingPrefix: "ZZ" });
    const label = { ...request, service: "standard", reference: "SHP-1" };

    const first = await carrier
      .createLabel(label, { idempotencyKey: "k" })
      .orThrow();

    const again = await carrier
      .createLabel(label, { idempotencyKey: "k" })
      .orThrow();

    const other = await carrier.createLabel(label).orThrow();

    expect(first.trackingNumber).toMatch(/^ZZ/);
    expect(again).toEqual(first);
    expect(other.labelId).not.toBe(first.labelId);
    expect((await carrier.track(first.trackingNumber)).ok).toBe(true);
  });

  it("refuses bad services", () => {
    expect(() =>
      flatRateCarrier({
        services: {
          mixed: { amount: money(1, "EUR"), additional: money(1, "USD") },
        },
      }),
    ).toThrow(TypeError);
  });

  it("has no webhook parser without a secret", () => {
    expect("parseWebhook" in flatRateCarrier({ services })).toBe(false);
  });

  it("checks the API version", () => {
    const carrier = flatRateCarrier({ services });

    expect(shipmentCarrierOf(carrier)).toBe(carrier);
    expect(() =>
      // @ts-expect-error a carrier for another API version
      shipmentCarrierOf({ ...carrier, apiVersion: 2 }),
    ).toThrow(/API 2/);
  });
});

describe("invalidShipmentRequest", () => {
  it("names the first problem", () => {
    expect(invalidShipmentRequest(request)).toBeUndefined();
    expect(
      invalidShipmentRequest({ ...request, from: { ...FROM, country: "nl" } })
        ?.hint,
    ).toBe("SHIPMENT_ADDRESS_INVALID");
    expect(
      invalidShipmentRequest({ ...request, to: { ...TO, city: " " } })?.hint,
    ).toBe("SHIPMENT_ADDRESS_INVALID");
    expect(invalidShipmentRequest({ ...request, parcels: [] })?.hint).toBe(
      "SHIPMENT_EMPTY",
    );
    expect(
      invalidShipmentRequest({ ...request, parcels: [{ weightGrams: 1.5 }] })
        ?.hint,
    ).toBe("SHIPMENT_PACKAGE_INVALID");
    expect(
      invalidShipmentRequest({
        ...request,
        parcels: [{ weightGrams: 1, heightMm: 0 }],
      })?.hint,
    ).toBe("SHIPMENT_PACKAGE_INVALID");
  });
});

describe("trackingUpdatesOf", () => {
  it("reads one update or a list", () => {
    const one = trackingUpdatesOf({
      trackingNumber: "FR1",
      events: [
        {
          id: "a",
          status: "delivered",
          occurredAt: AT,
          description: "At the door",
          location: "Berlin",
        },
        { id: "b", status: "in_transit", occurredAt: AT, description: "" },
      ],
    });

    expect(one.ok && one.data[0]?.events[0]).toMatchObject({
      id: "a",
      status: "delivered",
      description: "At the door",
      location: "Berlin",
    });
    expect(one.ok && one.data[0]?.events[1]).not.toHaveProperty("description");

    const many = trackingUpdatesOf([
      { trackingNumber: "A", events: [] },
      { trackingNumber: "B", events: [] },
    ]);

    expect(many.ok && many.data.map((update) => update.trackingNumber)).toEqual(
      ["A", "B"],
    );
  });

  it.each([
    ["no tracking number", { events: [] }],
    ["an empty tracking number", { trackingNumber: "", events: [] }],
    ["no events", { trackingNumber: "A" }],
    ["a non-object", "nope"],
    [
      "an event without an id",
      {
        trackingNumber: "A",
        events: [{ status: "delivered", occurredAt: AT }],
      },
    ],
    [
      "an unknown status",
      {
        trackingNumber: "A",
        events: [{ id: "a", status: "lost", occurredAt: AT }],
      },
    ],
    [
      "a bad time",
      {
        trackingNumber: "A",
        events: [{ id: "a", status: "delivered", occurredAt: "soon" }],
      },
    ],
    [
      "no time",
      { trackingNumber: "A", events: [{ id: "a", status: "delivered" }] },
    ],
  ])("refuses %s", (_name, payload) => {
    const result = trackingUpdatesOf(payload);

    expect(!result.ok && result.error.hint).toBe("SHIPMENT_TRACKING_INVALID");
  });
});
