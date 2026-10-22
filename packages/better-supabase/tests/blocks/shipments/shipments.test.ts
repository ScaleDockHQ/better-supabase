import { describe, expect, it, vi } from "vitest";

import type { ShipmentCarrier } from "../../../src/blocks/shipments/index.ts";

import {
  createShipments,
  flatRateCarrier,
  shipmentInputSchema,
  shipmentsBlock,
  shipmentsSection,
  shipmentSectionInputSchema,
  trackingEventInputSchema,
} from "../../../src/blocks/shipments/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { signWebhook } from "../../../src/core/signatures.ts";

const AT = "2026-10-22T08:00:00Z";
const LATER = "2026-10-22T12:00:00Z";
const SECRET = "whsec_c2hpcG1lbnRzLXRlc3Qtc2VjcmV0";

const FROM = {
  name: "Warehouse",
  company: "Acme",
  line1: "Dock 4",
  line2: "Gate B",
  city: "Rotterdam",
  postalCode: "3011",
  state: "ZH",
  country: "NL",
  phone: "+31",
  email: "ship@acme.test",
};

const TO = { line1: "Main St 1", city: "Berlin", country: "DE" };

const DRAFT = {
  id: "s1",
  organizationId: "org-1",
  reference: "SHP-1",
  status: "draft",
  from: FROM,
  to: TO,
  fromLocationId: null,
  subjectType: null,
  subjectId: null,
  carrier: null,
  service: null,
  trackingNumber: null,
  trackingUrl: null,
  labelId: null,
  labelUrl: null,
  labelFormat: null,
  labelCost: null,
  currency: null,
  labeledAt: null,
  deliveredAt: null,
  cancelledAt: null,
  createdBy: null,
  createdAt: AT,
  updatedAt: AT,
  packages: [
    {
      id: "k1",
      position: 1,
      weightGrams: 1200,
      lengthMm: 300,
      widthMm: 200,
      heightMm: 100,
      reference: "box",
    },
    {
      id: "k2",
      position: 2,
      weightGrams: 500,
      lengthMm: null,
      widthMm: null,
      heightMm: null,
      reference: null,
    },
  ],
};

const LABELED = {
  ...DRAFT,
  status: "label_created",
  fromLocationId: "l1",
  subjectType: "order",
  subjectId: "o1",
  carrier: "flat-rate",
  service: "standard",
  trackingNumber: "FR123",
  trackingUrl: "https://track.test/FR123",
  labelId: "label_123",
  labelUrl: "https://labels.test/123.pdf",
  labelFormat: "pdf",
  labelCost: "695",
  currency: "EUR",
  labeledAt: AT,
  deliveredAt: LATER,
  cancelledAt: LATER,
  createdBy: "u1",
  fields: { dock: "4" },
};

const EVENT = {
  id: "e1",
  externalId: "ev-1",
  status: "in_transit",
  occurredAt: AT,
  description: "Left the depot",
  location: "Rotterdam",
  source: "webhook",
  createdAt: AT,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        const result = results[fn];

        return Promise.resolve(
          // SAFETY: tests only store functions that take no arguments.
          typeof result === "function" ? (result as () => unknown)() : result,
        );
      },
    },
  };
}

const carrier = () =>
  flatRateCarrier({
    services: {
      standard: { amount: money(495, "EUR"), additional: money(200, "EUR") },
      express: { amount: money(1500, "EUR"), estimatedDays: 1 },
    },
    webhookSecret: SECRET,
  });

const instant = (value: string) => Temporal.Instant.from(value);

describe("createShipments", () => {
  it("creates a draft shipment in the block's tenant", async () => {
    const fake = fakeTransport({ create_shipment: DRAFT });

    const shipments = createShipments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const shipment = await shipments
      .create({
        from: FROM,
        to: TO,
        packages: [{ weightGrams: 1200 }],
        reference: "SHP-1",
        fromLocationId: "l1",
        subject: { type: "order", id: "o1" },
      })
      .orThrow();

    expect(fake.calls[0]).toEqual([
      "create_shipment",
      {
        tenant: "org-1",
        from_address: FROM,
        to_address: TO,
        packages: [{ weightGrams: 1200 }],
        reference: "SHP-1",
        from_location_id: "l1",
        subject_type: "order",
        subject_id: "o1",
      },
    ]);
    expect(shipment.status).toBe("draft");
    expect(shipment.from).toEqual(FROM);
    expect(shipment.to).toEqual(TO);
    expect(shipment.packages[0]?.lengthMm).toBe(300);
    expect(shipment.packages[1]).not.toHaveProperty("lengthMm");
    expect(shipment).not.toHaveProperty("labelCost");
    expect(shipment.fields).toEqual({});
  });

  it("defaults the optional inputs", async () => {
    const fake = fakeTransport({ create_shipment: DRAFT });

    const shipments = createShipments({
      transport: fake.transport,
      tenant: "org-1",
    });

    await shipments
      .create({ from: FROM, to: TO, packages: [{ weightGrams: 1 }] })
      .orThrow();

    expect(fake.calls[0]?.[1]).toMatchObject({
      reference: null,
      from_location_id: null,
      subject_type: null,
      subject_id: null,
    });
  });

  it("parses a labeled shipment", async () => {
    const shipments = createShipments({
      transport: fakeTransport({ get_shipment: LABELED }).transport,
    });

    const shipment = await shipments.get("s1").orThrow();

    expect(shipment?.labelCost).toEqual(money(695, "EUR"));
    expect(shipment?.subject).toEqual({ type: "order", id: "o1" });
    expect(shipment?.labelFormat).toBe("pdf");
    expect(shipment?.deliveredAt?.toString()).toBe(LATER);
    expect(shipment?.fields).toEqual({ dock: "4" });
  });

  it("returns null for a shipment it can't read", async () => {
    const shipments = createShipments({
      transport: fakeTransport({ get_shipment: null }).transport,
    });

    expect(await shipments.get("s9").orThrow()).toBeNull();
  });

  it("lists with filters and defaults", async () => {
    const fake = fakeTransport({ list_shipments: [DRAFT, LABELED] });

    const shipments = createShipments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const rows = await shipments
      .list({
        status: "draft",
        subject: { type: "order", id: "o1" },
        carrier: "flat-rate",
        before: instant(LATER),
        limit: 5,
      })
      .orThrow();

    await shipments.list().orThrow();

    expect(rows).toHaveLength(2);
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      status: "draft",
      subject_type: "order",
      subject_id: "o1",
      carrier: "flat-rate",
      before: LATER,
      page_size: 5,
    });
    expect(fake.calls[1]?.[1]).toMatchObject({ status: null, page_size: 50 });
  });

  it("fails without a tenant", async () => {
    const shipments = createShipments({
      transport: fakeTransport({}).transport,
    });

    expect((await shipments.list()).ok).toBe(false);
  });

  it("quotes every carrier, by currency and price", async () => {
    const other = flatRateCarrier({
      name: "other",
      services: {
        cheap: { amount: money(100, "EUR") },
        dollar: { amount: money(50, "USD") },
      },
    });

    const shipments = createShipments({
      transport: fakeTransport({ get_shipment: DRAFT }).transport,
      carriers: [carrier(), other],
    });

    const rates = await shipments.rates("s1").orThrow();

    expect(rates.map((rate) => `${rate.carrier}:${rate.service}`)).toEqual([
      "other:cheap",
      "flat-rate:standard",
      "flat-rate:express",
      "other:dollar",
    ]);
    expect(rates[1]?.amount).toEqual(money(695, "EUR"));

    const dollars = await shipments.rates("s1", { currency: "USD" }).orThrow();

    expect(dollars.map((rate) => rate.service)).toEqual(["dollar"]);
  });

  it("fails rates for a missing shipment or a failing carrier", async () => {
    const missing = createShipments({
      transport: fakeTransport({ get_shipment: null }).transport,
      carriers: [carrier()],
    });

    const gone = await missing.rates("s9");

    expect(!gone.ok && gone.error.kind).toBe("not_found");

    const broken: ShipmentCarrier = {
      ...carrier(),
      rates: () => AsyncResult.err(dbError("network", "down")),
    };

    const failing = createShipments({
      transport: fakeTransport({ get_shipment: DRAFT }).transport,
      carriers: [broken],
    });

    const result = await failing.rates("s1");

    expect(!result.ok && result.error.kind).toBe("network");
  });

  it("buys a label and stores it", async () => {
    const fake = fakeTransport({
      get_shipment: DRAFT,
      set_shipment_label: LABELED,
    });

    const shipments = createShipments({
      transport: fake.transport,
      carriers: [carrier()],
    });

    const shipment = await shipments
      .buyLabel("s1", { carrier: "flat-rate", service: "standard" })
      .orThrow();

    expect(shipment.status).toBe("label_created");

    const [, args] = fake.calls[1] ?? [];

    expect(args).toMatchObject({
      shipment_id: "s1",
      carrier: "flat-rate",
      service: "standard",
      label_cost: "695",
      currency: "EUR",
      label_format: "pdf",
      label_url: null,
      tracking_url: null,
    });
    expect(String(args?.["tracking_number"])).toMatch(/^FR/);
  });

  it("refuses a label for an unknown carrier or a labeled shipment", async () => {
    const shipments = createShipments({
      transport: fakeTransport({ get_shipment: LABELED }).transport,
      carriers: [carrier()],
    });

    const unknown = await shipments.buyLabel("s1", {
      carrier: "nobody",
      service: "standard",
    });

    expect(!unknown.ok && unknown.error.hint).toBe("SHIPMENT_CARRIER_UNKNOWN");

    const again = await shipments.buyLabel("s1", {
      carrier: "flat-rate",
      service: "standard",
    });

    expect(!again.ok && again.error.hint).toBe("SHIPMENT_NOT_DRAFT");
  });

  it("voids a label it fails to store", async () => {
    const cancel = vi.fn(() => AsyncResult.ok({ cancelled: true as const }));
    const voiding: ShipmentCarrier = { ...carrier(), cancel };

    const shipments = createShipments({
      transport: fakeTransport({
        get_shipment: DRAFT,
        set_shipment_label: () => {
          throw new Error("store failed");
        },
      }).transport,
      carriers: [voiding],
    });

    const result = await shipments.buyLabel("s1", {
      carrier: "flat-rate",
      service: "standard",
    });

    expect(result.ok).toBe(false);
    expect(cancel).toHaveBeenCalledOnce();
  });

  it("logs a label it can neither store nor void", async () => {
    const logger = { ...console, error: vi.fn() };

    const stuck: ShipmentCarrier = {
      ...carrier(),
      cancel: () => AsyncResult.err(dbError("network", "down")),
    };

    const shipments = createShipments({
      transport: fakeTransport({
        get_shipment: DRAFT,
        set_shipment_label: () => {
          throw new Error("store failed");
        },
      }).transport,
      carriers: [stuck],
      logger,
    });

    const result = await shipments.buyLabel("s1", {
      carrier: "flat-rate",
      service: "standard",
    });

    expect(result.ok).toBe(false);
    expect(logger.error).toHaveBeenCalledOnce();
  });

  it("refreshes tracking from the carrier", async () => {
    const tracked: ShipmentCarrier = {
      ...carrier(),
      track: () =>
        AsyncResult.ok([
          {
            id: "ev-1",
            status: "in_transit",
            occurredAt: instant(AT),
            description: "Left the depot",
          },
        ]),
    };

    const fake = fakeTransport({
      get_shipment: LABELED,
      record_tracking_events: {
        recorded: 1,
        shipment: { ...LABELED, status: "in_transit" },
      },
    });

    const shipments = createShipments({
      transport: fake.transport,
      carriers: [tracked],
    });

    const result = await shipments.refresh("s1").orThrow();

    expect(result.recorded).toBe(1);
    expect(result.shipment.status).toBe("in_transit");
    expect(fake.calls[1]).toEqual([
      "record_tracking_events",
      {
        shipment_id: "s1",
        source: "carrier",
        events: [
          {
            id: "ev-1",
            status: "in_transit",
            occurredAt: AT,
            description: "Left the depot",
            location: null,
          },
        ],
      },
    ]);
  });

  it("refuses to refresh a shipment without a label", async () => {
    const shipments = createShipments({
      transport: fakeTransport({ get_shipment: DRAFT }).transport,
      carriers: [carrier()],
    });

    const result = await shipments.refresh("s1");

    expect(!result.ok && result.error.hint).toBe("SHIPMENT_NOT_LABELED");
  });

  it("records tracking by hand", async () => {
    const fake = fakeTransport({
      record_tracking_events: { recorded: 0, shipment: LABELED },
    });

    const shipments = createShipments({ transport: fake.transport });

    const result = await shipments
      .recordTracking("s1", [
        {
          id: "m1",
          status: "delivered",
          occurredAt: instant(LATER),
          location: "Berlin",
        },
      ])
      .orThrow();

    expect(result.recorded).toBe(0);
    expect(fake.calls[0]?.[1]).toMatchObject({ source: "manual" });
  });

  it("ingests a signed webhook through the service transport", async () => {
    const user = fakeTransport({});

    const service = fakeTransport({
      ingest_tracking_events: (() => {
        let call = 0;

        return () => {
          call += 1;

          return call === 1
            ? {
                id: "s1",
                organizationId: "org-1",
                status: "delivered",
                recorded: 2,
              }
            : null;
        };
      })(),
    });

    const shipments = createShipments({
      transport: user.transport,
      service: service.transport,
      carriers: [carrier()],
    });

    const body = JSON.stringify([
      {
        trackingNumber: "FR123",
        events: [
          { id: "a", status: "in_transit", occurredAt: AT },
          { id: "b", status: "delivered", occurredAt: LATER },
        ],
      },
      { trackingNumber: "FR999", events: [] },
    ]);

    const headers = await signWebhook(SECRET, { id: "msg_1", body });

    const result = await shipments
      .ingest("flat-rate", { headers, body })
      .orThrow();

    expect(result).toEqual([
      {
        trackingNumber: "FR123",
        shipmentId: "s1",
        status: "delivered",
        recorded: 2,
      },
      { trackingNumber: "FR999", recorded: 0 },
    ]);
    expect(user.calls).toEqual([]);
    expect(service.calls[0]?.[1]).toMatchObject({
      carrier: "flat-rate",
      tracking_number: "FR123",
    });
  });

  it("refuses a forged webhook, a carrier without webhooks and a failed write", async () => {
    const shipments = createShipments({
      transport: fakeTransport({
        ingest_tracking_events: () => {
          throw new Error("write failed");
        },
      }).transport,
      carriers: [
        carrier(),
        flatRateCarrier({
          name: "pull-only",
          services: { standard: { amount: money(1, "EUR") } },
        }),
      ],
    });

    const body = JSON.stringify({ trackingNumber: "FR1", events: [] });

    const forged = await shipments.ingest("flat-rate", {
      headers: await signWebhook("whsec_b3RoZXItc2VjcmV0", { id: "m", body }),
      body,
    });

    expect(!forged.ok && forged.error.kind).toBe("unauthorized");

    const pull = await shipments.ingest("pull-only", { headers: {}, body });

    expect(!pull.ok && pull.error.hint).toBe("SHIPMENT_WEBHOOK_UNSUPPORTED");

    const failed = await shipments.ingest("flat-rate", {
      headers: await signWebhook(SECRET, { id: "m2", body }),
      body,
    });

    expect(failed.ok).toBe(false);
  });

  it("voids the label and cancels", async () => {
    const cancel = vi.fn(() => AsyncResult.ok({ cancelled: true as const }));

    const fake = fakeTransport({
      get_shipment: LABELED,
      cancel_shipment: { ...LABELED, status: "cancelled" },
    });

    const shipments = createShipments({
      transport: fake.transport,
      carriers: [{ ...carrier(), cancel }],
    });

    const shipment = await shipments.cancel("s1").orThrow();

    expect(shipment.status).toBe("cancelled");
    expect(cancel).toHaveBeenCalledWith(
      { labelId: "label_123", trackingNumber: "FR123" },
      { idempotencyKey: "void:s1" },
    );
  });

  it("cancels a draft without the carrier and refuses a shipped one", async () => {
    const fake = fakeTransport({
      get_shipment: DRAFT,
      cancel_shipment: { ...DRAFT, status: "cancelled" },
    });

    const shipments = createShipments({ transport: fake.transport });

    expect((await shipments.cancel("s1").orThrow()).status).toBe("cancelled");

    const shipped = createShipments({
      transport: fakeTransport({
        get_shipment: { ...LABELED, status: "in_transit" },
      }).transport,
    });

    const result = await shipped.cancel("s1");

    expect(!result.ok && result.error.hint).toBe("SHIPMENT_SHIPPED");
  });

  it("lists the tracking timeline", async () => {
    const shipments = createShipments({
      transport: fakeTransport({
        list_tracking_events: [
          EVENT,
          { ...EVENT, id: "e2", description: null, location: null },
        ],
      }).transport,
    });

    const events = await shipments.trackingEvents("s1").orThrow();

    expect(events[0]?.location).toBe("Rotterdam");
    expect(events[1]).not.toHaveProperty("location");
    expect(events[0]?.occurredAt.toString()).toBe(AT);
  });
});

describe("shipments block", () => {
  it("declares its SQL module, section and recipes", () => {
    expect(shipmentsBlock.name).toBe("shipments");
    expect(shipmentsBlock.sql).toEqual(["shipments"]);
    expect(shipmentsBlock.recipes).toEqual(["shipment-tracking"]);
  });

  it("validates the inputs", async () => {
    const good = await shipmentInputSchema["~standard"].validate({
      from: FROM,
      to: TO,
      packages: [{ weightGrams: 1 }],
    });

    const section = await shipmentSectionInputSchema["~standard"].validate({
      from: FROM,
      to: TO,
      packages: [{ weightGrams: 1 }],
      reference: "",
    });

    const event = await trackingEventInputSchema["~standard"].validate({
      id: "e",
      status: "teleported",
      occurredAt: AT,
    });

    expect(good.issues).toBeUndefined();
    expect(section.issues?.length).toBeGreaterThan(0);
    expect(event.issues?.length).toBeGreaterThan(0);
  });

  it("loads and writes the shipments of a record", async () => {
    const fake = fakeTransport({
      list_shipments: [DRAFT],
      create_shipment: DRAFT,
      get_shipment: DRAFT,
      cancel_shipment: { ...DRAFT, status: "cancelled" },
    });

    const shipments = createShipments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const subject = { type: "order", id: "o1" };

    const rows = await shipmentsSection
      .load(shipments, subject, undefined)
      .orThrow();

    await shipmentsSection.writes.create
      .run(shipments, subject, {
        from: FROM,
        to: TO,
        packages: [{ weightGrams: 1 }],
      })
      .orThrow();

    const cancelled = await shipmentsSection.writes.cancel
      .run(shipments, subject, { id: "s1" })
      .orThrow();

    expect(rows).toHaveLength(1);
    expect(cancelled.status).toBe("cancelled");
    expect(fake.calls[1]?.[1]).toMatchObject({
      subject_type: "order",
      subject_id: "o1",
    });
  });
});
