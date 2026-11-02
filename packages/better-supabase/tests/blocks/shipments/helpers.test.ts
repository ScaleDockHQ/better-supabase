import { describe, expect, it } from "vitest";

import {
  createShipments,
  flatRateCarrier,
} from "../../../src/blocks/shipments/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T08:00:00Z";

const ADDRESS = { line1: "Main St 1", city: "Berlin", country: "DE" };

const SHIPMENT = {
  id: "s1",
  organizationId: "org-1",
  reference: "SHP-1",
  status: "draft",
  from: ADDRESS,
  to: ADDRESS,
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
  packages: [{ id: "k1", position: 1, weightGrams: 1200 }],
};

function setup() {
  const t = fieldsTransport({
    get_shipment: () => SHIPMENT,
    set_shipment_label: () => ({ ...SHIPMENT, status: "label_created" }),
  });

  const shipments = createShipments({
    transport: t,
    tenant: "org-1",
    carriers: [
      flatRateCarrier({
        name: "post",
        services: {
          cheap: { amount: money(100, "EUR") },
          fast: { amount: money(900, "EUR"), estimatedDays: 1 },
          dollar: { amount: money(50, "USD") },
        },
      }),
    ],
  });

  return { shipments, t };
}

describe("shipments helpers", () => {
  it("shipCheapest buys the label of the cheapest quote", async () => {
    const { shipments, t } = setup();

    const shipment = await shipments.shipCheapest({ id: "s1" }).orThrow();

    expect(shipment.status).toBe("label_created");
    expect(t.calls.at(-1)?.[1]).toMatchObject({
      carrier: "post",
      service: "dollar",
    });
  });

  it("shipCheapest respects the currency", async () => {
    const { shipments, t } = setup();

    await shipments.shipCheapest({ id: "s1", currency: "EUR" }).orThrow();

    expect(t.calls.at(-1)?.[1]).toMatchObject({ service: "cheap" });
  });

  it("shipCheapest fails without a matching quote and buys nothing", async () => {
    const { shipments, t } = setup();
    const result = await shipments.shipCheapest({ id: "s1", currency: "GBP" });

    expect(result.ok ? undefined : result.error).toMatchObject({
      hint: "SHIPMENT_NO_RATE",
    });

    expect(t.calls.map(([fn]) => fn)).not.toContain("set_shipment_label");
  });
});
