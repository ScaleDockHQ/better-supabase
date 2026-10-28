import { describe, expect, it } from "vitest";

import { createInventory } from "../../../src/blocks/inventory/index.ts";
import { money } from "../../../src/commerce/index.ts";

function recorder(...results: unknown[]) {
  const calls: { fn: string; args: unknown }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        calls.push({ fn, args });

        return Promise.resolve(
          results.length > 1 ? results.shift() : results[0],
        );
      },
    },
  };
}

const ALLOCATION = {
  id: "a1",
  variantId: "v1",
  locationId: "l1",
  documentType: "order",
  documentId: "o1",
  lineId: "ol1",
  quantity: "12.000000",
  allocated: "10.500000",
  fulfilled: "0.000000",
  backordered: "1.500000",
  status: "open",
  createdAt: "2026-10-28T19:00:45.068251+00:00",
};

describe("inventory tracking", () => {
  it("sets a stock item, a bin and a lot", async () => {
    const { calls, transport } = recorder(
      {
        variantId: "v1",
        unit: "kg",
        scale: 3,
        tracking: "lot",
        tracksExpiry: true,
        costing: "average",
        currency: "EUR",
        averageCost: null,
      },
      { id: "b1", code: "HOLD", hold: true, active: true },
      { id: "lot1", code: "L1", expiresOn: "2030-02-01" },
      { id: "lot2", code: "L2", expiresOn: null },
    );

    const inventory = createInventory({ transport });

    expect(
      await inventory
        .setStockItem("v1", {
          unit: "kg",
          scale: 3,
          tracking: "lot",
          tracksExpiry: true,
          costing: "average",
          currency: "EUR",
        })
        .orThrow(),
    ).toEqual({
      variantId: "v1",
      unit: "kg",
      scale: 3,
      tracking: "lot",
      tracksExpiry: true,
      costing: "average",
      currency: "EUR",
      averageCost: null,
    });
    expect(
      await inventory.saveBin("l1", { code: "HOLD", hold: true }).orThrow(),
    ).toEqual({ id: "b1", code: "HOLD", hold: true, active: true });
    expect(await inventory.saveLot("v1", "L1", "2030-02-01").orThrow()).toEqual(
      { id: "lot1", code: "L1", expiresOn: "2030-02-01" },
    );
    expect(await inventory.saveLot("v1", "L2").orThrow()).toEqual({
      id: "lot2",
      code: "L2",
      expiresOn: null,
    });
    expect(calls).toEqual([
      {
        fn: "set_stock_item",
        args: {
          variant: "v1",
          unit: "kg",
          scale: 3,
          tracking: "lot",
          tracks_expiry: true,
          costing: "average",
          currency: "EUR",
        },
      },
      {
        fn: "save_bin",
        args: {
          location: "l1",
          bin: null,
          code: "HOLD",
          name: null,
          hold: true,
          active: null,
        },
      },
      {
        fn: "save_lot",
        args: { variant: "v1", code: "L1", expires_on: "2030-02-01" },
      },
      { fn: "save_lot", args: { variant: "v1", code: "L2", expires_on: null } },
    ]);
  });

  it("defaults a stock item's settings to null", async () => {
    const { calls, transport } = recorder({
      variantId: "v1",
      unit: "item",
      scale: 0,
      tracking: "none",
      tracksExpiry: false,
      costing: "none",
      currency: null,
      averageCost: null,
    });

    await createInventory({ transport }).setStockItem("v1", {}).orThrow();

    expect(calls[0]?.args).toEqual({
      variant: "v1",
      unit: null,
      scale: null,
      tracking: null,
      tracks_expiry: null,
      costing: null,
      currency: null,
    });
  });

  it("reads the stock detail, expiring lots and the valuation", async () => {
    const { calls, transport } = recorder(
      {
        variantId: "v1",
        locationId: "l1",
        onHand: "10.500000",
        reserved: "0",
        held: "0.500000",
        available: "10.000000",
        unbinned: "0",
        buckets: [
          {
            binId: "b1",
            binCode: "HOLD",
            hold: true,
            lotId: "lot1",
            lotCode: "L1",
            expiresOn: "2030-02-01",
            onHand: "0.500000",
          },
        ],
        serials: ["SN-1"],
      },
      [
        {
          lotId: "lot1",
          code: "L1",
          variantId: "v1",
          locationId: "l1",
          binId: null,
          expiresOn: "2030-02-01",
          onHand: "10.000000",
        },
      ],
      3,
      {
        variantId: "v1",
        costing: "average",
        averageCost: "200.000000",
        onHand: "10.500000",
        currency: "EUR",
        value: "2100",
      },
      {
        variantId: "v1",
        costing: "none",
        averageCost: null,
        onHand: "1",
        currency: null,
        value: null,
      },
    );

    const inventory = createInventory({ transport });

    expect(await inventory.stockDetail("v1", "l1").orThrow()).toEqual({
      variantId: "v1",
      locationId: "l1",
      onHand: 10.5,
      reserved: 0,
      held: 0.5,
      available: 10,
      unbinned: 0,
      buckets: [
        {
          binId: "b1",
          binCode: "HOLD",
          hold: true,
          lotId: "lot1",
          lotCode: "L1",
          expiresOn: "2030-02-01",
          onHand: 0.5,
        },
      ],
      serials: ["SN-1"],
    });
    expect(await inventory.expiringLots("org", "2030-03-01").orThrow()).toEqual(
      [
        {
          lotId: "lot1",
          code: "L1",
          variantId: "v1",
          locationId: "l1",
          binId: null,
          expiresOn: "2030-02-01",
          onHand: 10,
        },
      ],
    );
    expect(await inventory.expireLots("org").orThrow()).toBe(3);
    expect(await inventory.stockValuation("v1").orThrow()).toEqual({
      variantId: "v1",
      costing: "average",
      averageCost: "200.000000",
      onHand: 10.5,
      value: money(2100n, "EUR"),
    });
    expect((await inventory.stockValuation("v1").orThrow()).value).toBeNull();
    expect(calls.map((call) => call.args)).toEqual([
      { variant: "v1", location: "l1" },
      { tenant: "org", before: "2030-03-01" },
      { tenant: "org", as_of: null },
      { variant: "v1" },
      { variant: "v1" },
    ]);
  });

  it("allocates, fulfills, restores, releases and lists allocations", async () => {
    const { calls, transport } = recorder(
      ALLOCATION,
      { ...ALLOCATION, fulfilled: "2", movementId: "m1" },
      { ...ALLOCATION, fulfilled: "1" },
      1,
      [{ ...ALLOCATION, status: "released" }],
    );

    const inventory = createInventory({ transport });

    const allocation = await inventory
      .allocate("org", {
        variantId: "v1",
        locationId: "l1",
        quantity: 12,
        documentType: "order",
        documentId: "o1",
        lineId: "ol1",
      })
      .orThrow();

    expect(allocation).toMatchObject({
      id: "a1",
      quantity: 12,
      allocated: 10.5,
      backordered: 1.5,
      status: "open",
    });
    expect(allocation.createdAt.epochMilliseconds).toBe(
      Date.parse("2026-10-28T19:00:45.068Z"),
    );
    expect(allocation).not.toHaveProperty("movementId");
    expect(
      await inventory
        .fulfillAllocation("a1", 2, { lot: { code: "L1" } })
        .orThrow(),
    ).toMatchObject({ fulfilled: 2, movementId: "m1" });
    expect(await inventory.restoreAllocation("a1", 1).orThrow()).toMatchObject({
      fulfilled: 1,
    });
    expect(
      await inventory.releaseAllocations("org", "order", "o1").orThrow(),
    ).toBe(1);
    expect(
      (await inventory.listAllocations("org", "order", "o1").orThrow()).map(
        (row) => row.status,
      ),
    ).toEqual(["released"]);
    expect(calls).toEqual([
      {
        fn: "allocate_stock",
        args: {
          tenant: "org",
          variant: "v1",
          location: "l1",
          quantity: 12,
          document_type: "order",
          document_id: "o1",
          line_id: "ol1",
          backorder: true,
        },
      },
      {
        fn: "fulfill_allocation",
        args: {
          allocation: "a1",
          quantity: 2,
          detail: { lot: { code: "L1" } },
        },
      },
      {
        fn: "restore_allocation",
        args: { allocation: "a1", quantity: 1, detail: null },
      },
      {
        fn: "release_allocations",
        args: { tenant: "org", document_type: "order", document_id: "o1" },
      },
      {
        fn: "list_allocations",
        args: { tenant: "org", document_type: "order", document_id: "o1" },
      },
    ]);
  });

  it("refuses an allocation with an unknown status", async () => {
    const { transport } = recorder([{ ...ALLOCATION, status: "lost" }]);

    const result = await createInventory({ transport }).listAllocations(
      "org",
      "order",
      "o1",
    );

    expect(result.ok).toBe(false);
  });
});
