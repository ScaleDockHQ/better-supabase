import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import {
  createShipments,
  flatRateCarrier,
} from "../../src/blocks/shipments/index.ts";
import { money } from "../../src/commerce/money.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { signWebhook } from "../../src/core/signatures.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "shipments"];
const SECRET = "whsec_aW50ZWdyYXRpb24tc2hpcG1lbnRz";

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const carrier = flatRateCarrier({
  services: {
    standard: { amount: money(495, "EUR"), additional: money(200, "EUR") },
    express: { amount: money(1500, "EUR"), estimatedDays: 1 },
  },
  webhookSecret: SECRET,
});

const input = {
  from: { line1: "Dock 4", city: "Rotterdam", country: "NL" },
  to: { line1: "Main St 1", city: "Berlin", country: "DE" },
  packages: [{ weightGrams: 1000 }, { weightGrams: 500, lengthMm: 300 }],
};

describe.skipIf(!live)("shipments", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("labels a shipment, tracks it and ingests a signed carrier webhook", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("shipper");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      await s.install(MODULES);
      const tenant = await s.organization(owner, { member });
      await s.organization(outsider);

      const shipments = createShipments({
        transport: sqlTransport(s.sql),
        tenant,
        carriers: [carrier],
      });

      await s.as(owner);

      const draft = await shipments
        .create({ ...input, reference: "SHP-1" })
        .orThrow();

      expect(draft).toMatchObject({ status: "draft", reference: "SHP-1" });
      expect(draft.packages.map((parcel) => parcel.weightGrams)).toEqual([
        1000, 500,
      ]);

      const rates = await shipments.rates(draft.id).orThrow();

      expect(rates.map((rate) => [rate.service, rate.amount])).toEqual([
        ["standard", money(695, "EUR")],
        ["express", money(3000, "EUR")],
      ]);

      const labeled = await shipments
        .buyLabel(draft.id, { carrier: "flat-rate", service: "standard" })
        .orThrow();

      expect(labeled).toMatchObject({
        status: "label_created",
        carrier: "flat-rate",
        labelCost: money(695, "EUR"),
      });
      expect(
        await shipments
          .buyLabel(draft.id, { carrier: "flat-rate", service: "express" })
          .then(hint),
      ).toBe("SHIPMENT_NOT_DRAFT");

      const trackingNumber = labeled.trackingNumber ?? "";

      const moved = await shipments
        .recordTracking(draft.id, [
          {
            id: "scan-1",
            status: "in_transit",
            occurredAt: Temporal.Instant.from("2030-01-07T10:00:00Z"),
            location: "Utrecht",
          },
        ])
        .orThrow();

      expect(moved).toMatchObject({
        recorded: 1,
        shipment: { status: "in_transit" },
      });

      const body = JSON.stringify({
        trackingNumber,
        events: [
          {
            id: "scan-2",
            status: "delivered",
            occurredAt: "2030-01-07T15:00:00Z",
          },
        ],
      });

      const headers = await signWebhook(SECRET, { id: "msg_1", body });

      await s.service();

      const ingested = await shipments
        .ingest("flat-rate", { headers, body })
        .orThrow();

      expect(ingested).toEqual([
        {
          trackingNumber,
          shipmentId: draft.id,
          status: "delivered",
          recorded: 1,
        },
      ]);
      expect(
        (await shipments.ingest("flat-rate", { headers, body }).orThrow())[0]
          ?.recorded,
      ).toBe(0);

      const forged = await signWebhook("whsec_Zm9yZ2Vk", { id: "msg_2", body });

      expect(
        await shipments
          .ingest("flat-rate", { headers: forged, body })
          .then((result) => (result.ok ? "ok" : result.error.kind)),
      ).toBe("unauthorized");

      await s.as(owner);

      expect(
        (await shipments.trackingEvents(draft.id).orThrow()).map(
          (event) => event.status,
        ),
      ).toEqual(["label_created", "in_transit", "delivered"]);
      expect(await shipments.cancel(draft.id).then(hint)).toBe(
        "SHIPMENT_SHIPPED",
      );

      await s.as(member);

      expect((await shipments.get(draft.id).orThrow())?.status).toBe(
        "delivered",
      );
      expect(await shipments.create(input).then(hint)).toBe(
        "SHIPMENT_FORBIDDEN",
      );

      await s.as(outsider);

      expect(await shipments.get(draft.id).orThrow()).toBeNull();

      await s.client.query("reset role");

      expect(
        (
          await s.rows<{ type: string }>(
            "select type from better_supabase.outbox_events where organization_id = $1 and type like 'shipment.%' order by position",
            [tenant],
          )
        ).map((row) => row.type),
      ).toEqual([
        "shipment.created",
        "shipment.labeled",
        "shipment.status_changed",
        "shipment.status_changed",
        "shipment.status_changed",
      ]);
    } finally {
      await s.close();
    }
  });

  it("voids the label when it cancels a labeled shipment", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("shipper");
      await s.install(MODULES);
      const tenant = await s.organization(owner);

      const shipments = createShipments({
        transport: sqlTransport(s.sql),
        tenant,
        carriers: [carrier],
      });

      await s.as(owner);

      const draft = await shipments.create(input).orThrow();

      expect(draft.reference).toMatch(/^SHP-[0-9A-F]{10}$/);

      await shipments
        .buyLabel(draft.id, { carrier: "flat-rate", service: "express" })
        .orThrow();

      const cancelled = await shipments.cancel(draft.id).orThrow();

      expect(cancelled.status).toBe("cancelled");
      expect(cancelled.cancelledAt).toBeInstanceOf(Temporal.Instant);
      expect(
        await shipments.list({ status: "cancelled" }).orThrow(),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });
});
