import { describe, expect, it } from "vitest";

import { createShipments } from "../../../src/blocks/shipments/index.ts";
import { lineOf } from "../../../src/blocks/shipments/lines.ts";

const AT = "2026-10-22T08:00:00Z";

const SHIPMENT = {
  id: "s1",
  organizationId: "org-1",
  reference: "SHP-1",
  status: "draft",
  from: { line1: "Dam 1", city: "Amsterdam", country: "NL" },
  to: { line1: "Main St 1", city: "Berlin", country: "DE" },
  fromLocationId: "l1",
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
  packages: [],
  lines: [
    {
      id: "sl1",
      position: 1,
      direction: "outbound",
      variantId: "v1",
      locationId: "l1",
      quantity: "1.250000",
      allocationId: "a1",
      detail: { parts: [{ lotId: "lot-1", quantity: "1.250000" }] },
      disposition: null,
      movementId: "m1",
      movedAt: AT,
    },
  ],
};

function recorder(result: unknown) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });

        return Promise.resolve(result);
      },
    },
  };
}

describe("shipment lines", () => {
  it("sets the lines of a draft", async () => {
    const { calls, transport } = recorder(SHIPMENT);
    const shipments = createShipments({ transport, tenant: "org-1" });

    const shipment = await shipments
      .setLines({
        id: "s1",
        lines: [
          {
            variantId: "v1",
            locationId: "l1",
            quantity: 1.25,
            allocationId: "a1",
            detail: { lotId: "lot-1" },
          },
          { variantId: "v2", locationId: "l1", quantity: "2" },
        ],
      })
      .orThrow();

    expect(calls).toEqual([
      {
        fn: "set_shipment_lines",
        args: {
          shipment_id: "s1",
          lines: [
            {
              variantId: "v1",
              locationId: "l1",
              quantity: "1.25",
              allocationId: "a1",
              detail: { lotId: "lot-1" },
            },
            { variantId: "v2", locationId: "l1", quantity: "2" },
          ],
        },
      },
    ]);
    expect(shipment.lines).toEqual([
      {
        id: "sl1",
        position: 1,
        direction: "outbound",
        variantId: "v1",
        locationId: "l1",
        quantity: "1.250000",
        allocationId: "a1",
        detail: { parts: [{ lotId: "lot-1", quantity: "1.250000" }] },
        movementId: "m1",
        movedAt: Temporal.Instant.from(AT),
      },
    ]);
  });

  it("receives a return with its disposition", async () => {
    const { calls, transport } = recorder({ ...SHIPMENT, status: "delivered" });
    const shipments = createShipments({ transport, tenant: "org-1" });

    await shipments
      .receiveReturn({
        id: "s1",
        lines: [
          {
            variantId: "v1",
            locationId: "l1",
            quantity: 0.5,
            disposition: "hold",
            detail: { binId: "b-hold" },
          },
          {
            variantId: "v1",
            locationId: "l1",
            quantity: 1,
            disposition: "scrap",
          },
        ],
      })
      .orThrow();

    expect(calls[0]).toEqual({
      fn: "receive_shipment_return",
      args: {
        shipment_id: "s1",
        lines: [
          {
            variantId: "v1",
            locationId: "l1",
            quantity: "0.5",
            disposition: "hold",
            detail: { binId: "b-hold" },
          },
          {
            variantId: "v1",
            locationId: "l1",
            quantity: "1",
            disposition: "scrap",
          },
        ],
      },
    });
  });

  it("parses a bare return line", () => {
    expect(
      lineOf({
        id: "sl2",
        position: 2,
        direction: "return",
        variantId: "v1",
        locationId: "l1",
        quantity: "0.500000",
        allocationId: null,
        detail: null,
        disposition: "restock",
        movementId: null,
        movedAt: null,
      }),
    ).toEqual({
      id: "sl2",
      position: 2,
      direction: "return",
      variantId: "v1",
      locationId: "l1",
      quantity: "0.500000",
      disposition: "restock",
    });
  });

  it("rejects an unknown disposition", () => {
    expect(() =>
      lineOf({
        id: "sl3",
        position: 3,
        direction: "return",
        variantId: "v1",
        locationId: "l1",
        quantity: "1",
        disposition: "melt",
      }),
    ).toThrow(/disposition/);
  });
});
