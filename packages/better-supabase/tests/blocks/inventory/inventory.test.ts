import { describe, expect, it } from "vitest";

import type { Inventory } from "../../../src/blocks/inventory/index.ts";

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

describe("inventory block", () => {
  it("reads the overview in one call", async () => {
    const { calls, transport } = recorder({
      levelCount: 4,
      lowStockCount: 2,
      lowStock: [
        {
          variantId: "v1",
          locationId: "l1",
          onHand: "2.000000",
          available: "1.000000",
          reorderPoint: "5.000000",
        },
      ],
      expiring: [],
    });

    const overview = await createInventory({ transport })
      .overview({ organizationId: "o", limit: 5, expiryDays: 14 })
      .orThrow();

    expect(calls).toEqual([
      {
        fn: "inventory_overview",
        args: { tenant: "o", row_limit: 5, expiry_days: 14 },
      },
    ]);
    expect(overview.lowStockCount).toBe(2);
    expect(overview.lowStock[0]?.reorderPoint).toBe("5.000000");
  });

  it("saves locations and adjusts stock", async () => {
    const { calls, transport } = recorder(
      { id: "l1", code: "WH-1", active: true },
      { movementId: "m1", onHand: 10, available: 8 },
    );

    const inventory = createInventory({ transport });
    expect(
      await inventory
        .saveLocation({
          organizationId: "org",
          input: { code: "WH-1", name: "Main" },
        })
        .orThrow(),
    ).toEqual({ id: "l1", code: "WH-1", active: true });
    expect(
      await inventory
        .adjustStock({
          variantId: "v1",
          locationId: "l1",
          quantity: 10,
          reason: "receipt",
        })
        .orThrow(),
    ).toEqual({ movementId: "m1", onHand: 10, available: 8 });
    expect(calls).toEqual([
      {
        fn: "save_location",
        args: {
          tenant: "org",
          location: null,
          code: "WH-1",
          name: "Main",
          kind: null,
        },
      },
      {
        fn: "adjust_stock",
        args: {
          variant: "v1",
          location: "l1",
          quantity: 10,
          reason: "receipt",
          note: null,
          detail: null,
        },
      },
    ]);
  });

  it("reads a count that wrote no movement", async () => {
    const { transport } = recorder({ movementId: null, delta: 0, onHand: 5 });
    expect(
      await createInventory({ transport })
        .countStock({ variantId: "v1", locationId: "l1", counted: 5 })
        .orThrow(),
    ).toEqual({ movementId: null, delta: 0, onHand: 5 });
  });

  it("reserves with an instant expiry and commits to a movement id", async () => {
    const { calls, transport } = recorder(
      { id: "r1", expiresAt: "2026-10-14T10:15:00Z", available: 3 },
      { id: "r1", movementId: "m2" },
    );

    const inventory = createInventory({ transport });

    const held = await inventory
      .reserve({
        variantId: "v1",
        locationId: "l1",
        input: {
          quantity: 2,
          referenceType: "cart",
          referenceId: "c1",
          expiresAt: Temporal.Instant.from("2026-10-14T10:15:00Z"),
        },
      })
      .orThrow();

    expect(held.expiresAt.toString()).toBe("2026-10-14T10:15:00Z");
    expect(await inventory.commitReservation("r1").orThrow()).toBe("m2");
    expect(calls[0]?.args).toMatchObject({
      quantity: 2,
      reference_type: "cart",
      expires_at: "2026-10-14T10:15:00Z",
    });
  });

  it("expires reservations through the service transport and the job", async () => {
    const member = recorder(0);
    const service = recorder(4);

    const inventory = createInventory({
      transport: member.transport,
      service: service.transport,
    });

    expect(await inventory.expireReservations().orThrow()).toBe(4);
    await inventory.job(
      { maxRows: 50 },
      Object.create(null),
      new AbortController().signal,
    );
    expect(service.calls).toEqual([
      { fn: "expire_reservations", args: { max_rows: null } },
      { fn: "expire_reservations", args: { max_rows: 50 } },
    ]);
    expect(member.calls).toEqual([]);
  });

  it("sends purchase order lines as minor units and refuses a mixed currency", async () => {
    const { calls, transport } = recorder({ id: "po1", status: "draft" });
    const inventory = createInventory({ transport });
    await inventory
      .savePurchaseOrder({
        organizationId: "org",
        input: {
          locationId: "l1",
          supplier: { type: "company", id: "acme" },
          currency: "EUR",
          lines: [
            { variantId: "v1", quantity: 10, unitCost: money(450n, "EUR") },
          ],
        },
      })
      .orThrow();
    expect(calls[0]?.args).toMatchObject({
      supplier_type: "company",
      supplier_id: "acme",
      lines: [{ variantId: "v1", quantity: 10, unitCost: "450" }],
    });

    const mixed = await inventory.savePurchaseOrder({
      organizationId: "org",
      input: {
        locationId: "l1",
        currency: "EUR",
        lines: [{ variantId: "v1", quantity: 1, unitCost: money(450n, "USD") }],
      },
    });

    expect(mixed).toMatchObject({
      ok: false,
      error: { hint: "INVENTORY_CURRENCY_INVALID" },
    });
    expect(calls).toHaveLength(1);
  });

  it("sends the tax of purchase order lines and reads the tax lines back", async () => {
    const { calls, transport } = recorder(
      { id: "po1", status: "draft" },
      {
        currency: "EUR",
        lines: [
          {
            taxCode: "NL-21",
            taxRateBps: 2100,
            net: "5015",
            tax: "1053",
            gross: "6068",
          },
          { taxRateBps: 900, net: "1000", tax: "90", gross: "1090" },
        ],
      },
    );

    const inventory = createInventory({ transport });
    await inventory
      .savePurchaseOrder({
        organizationId: "org",
        input: {
          locationId: "l1",
          currency: "EUR",
          lines: [
            {
              variantId: "v1",
              quantity: 3,
              unitCost: money(1005n, "EUR"),
              taxRateBps: 2100,
              taxCode: "NL-21",
            },
            { variantId: "v2", quantity: 1, unitCost: money(1000n, "EUR") },
          ],
        },
      })
      .orThrow();
    expect(calls[0]?.args).toEqual(
      expect.objectContaining({
        lines: [
          {
            variantId: "v1",
            quantity: 3,
            unitCost: "1005",
            taxRateBps: 2100,
            taxCode: "NL-21",
          },
          { variantId: "v2", quantity: 1, unitCost: "1000" },
        ],
      }),
    );

    expect(await inventory.purchaseOrderTaxLines("po1").orThrow()).toEqual([
      {
        taxCode: "NL-21",
        taxRateBps: 2100,
        net: money(5015n, "EUR"),
        tax: money(1053n, "EUR"),
        gross: money(6068n, "EUR"),
      },
      {
        taxRateBps: 900,
        net: money(1000n, "EUR"),
        tax: money(90n, "EUR"),
        gross: money(1090n, "EUR"),
      },
    ]);
    expect(calls[1]).toEqual({
      fn: "purchase_order_tax_lines",
      args: { purchase_order: "po1" },
    });
  });

  it("maps a partial receipt and refuses an unknown status", async () => {
    const { transport } = recorder(
      { status: "partially_received", backordered: 4 },
      { status: "lost", backordered: 0 },
    );

    const inventory = createInventory({ transport });
    expect(
      await inventory
        .receivePurchaseOrder({
          purchaseOrderId: "po1",
          lines: [{ lineId: "x1", quantity: 6 }],
        })
        .orThrow(),
    ).toEqual({ status: "partially_received", backordered: 4 });
    expect(
      (
        await inventory.receivePurchaseOrder({
          purchaseOrderId: "po1",
          lines: [],
        })
      ).ok,
    ).toBe(false);
  });

  it("runs hooks around methods", async () => {
    const { calls, transport } = recorder({ id: "t1" });
    const seen: string[] = [];

    const inventory = createInventory({
      transport,
      hooks: {
        createTransfer: {
          before: ([{ organizationId, input }]) => [
            { organizationId, input: { ...input, note: "checked" } },
          ],
          after: (result, _args, info) => {
            seen.push(`${info.method} ${String(result.ok)}`);
          },
        },
      },
    });

    await inventory
      .createTransfer({
        organizationId: "org",
        input: {
          fromLocationId: "a",
          toLocationId: "b",
          lines: [{ variantId: "v1", quantity: 1 }],
        },
      })
      .orThrow();
    expect(calls[0]?.args).toMatchObject({ note: "checked" });
    expect(seen).toEqual(["createTransfer true"]);
  });

  it("calls one function per method", async () => {
    const cases: [
      string,
      unknown,
      (inventory: Inventory) => Promise<unknown>,
    ][] = [
      [
        "set_location_active",
        true,
        (i) =>
          i.setLocationActive({ locationId: "l1", active: false }).orThrow(),
      ],
      [
        "set_location_address",
        true,
        (i) =>
          i
            .setLocationAddress({
              locationId: "l1",
              address: { city: "Amsterdam", country: "NL" },
            })
            .orThrow(),
      ],
      ["delete_location", true, (i) => i.deleteLocation("l1").orThrow()],
      [
        "set_reorder_point",
        true,
        (i) =>
          i
            .setReorderPoint({
              variantId: "v1",
              locationId: "l1",
              reorderPoint: 10,
            })
            .orThrow(),
      ],
      [
        "release_reservation",
        true,
        (i) => i.releaseReservation("r1").orThrow(),
      ],
      ["ship_transfer", true, (i) => i.shipTransfer("t1").orThrow()],
      ["receive_transfer", true, (i) => i.receiveTransfer("t1").orThrow()],
      ["cancel_transfer", true, (i) => i.cancelTransfer("t1").orThrow()],
      [
        "place_purchase_order",
        true,
        (i) => i.placePurchaseOrder("po1").orThrow(),
      ],
      [
        "cancel_purchase_order",
        true,
        (i) => i.cancelPurchaseOrder("po1").orThrow(),
      ],
    ];

    for (const [fn, result, run] of cases) {
      const { calls, transport } = recorder(result);
      await run(createInventory({ transport }));
      expect(calls.map((call) => call.fn)).toEqual([fn]);
    }
  });

  it("runs the job with no payload", async () => {
    const { calls, transport } = recorder(0);
    await createInventory({ transport }).job(
      undefined,
      Object.create(null),
      new AbortController().signal,
    );
    expect(calls).toEqual([
      { fn: "expire_reservations", args: { max_rows: null } },
    ]);
  });
});

describe("inventory levels and movements reads", () => {
  it("reads the levels of the given variants in one call", async () => {
    const calls: { fn: string; args: unknown }[] = [];

    const inventory = createInventory({
      transport: {
        call(_schema: string, fn: string, args: unknown) {
          calls.push({ fn, args });

          return Promise.resolve([
            {
              variantId: "v1",
              locationId: "l1",
              onHand: "5",
              allocated: "1",
              available: "4",
              incoming: "0",
              reorderPoint: null,
              status: "in_stock",
            },
          ]);
        },
      },
    });

    const levels = await inventory
      .levels({ organizationId: "org", variantIds: ["v1", "v2"] })
      .orThrow();

    expect(levels).toEqual([
      {
        variantId: "v1",
        locationId: "l1",
        onHand: "5",
        allocated: "1",
        available: "4",
        incoming: "0",
        reorderPoint: null,
        status: "in_stock",
      },
    ]);
    expect(calls).toEqual([
      {
        fn: "inventory_levels",
        args: { tenant: "org", variant_ids: ["v1", "v2"], location_id: null },
      },
    ]);
  });

  it("pages movements with the filters it is given", async () => {
    const calls: { fn: string; args: unknown }[] = [];

    const inventory = createInventory({
      transport: {
        call(_schema: string, fn: string, args: unknown) {
          calls.push({ fn, args });

          return Promise.resolve([
            {
              id: "m1",
              kind: "stock.sale",
              variantId: "v1",
              locationId: "l1",
              binId: null,
              lotId: null,
              quantity: "-2",
              documentType: "order",
              documentId: "o1",
              effectiveAt: "2026-11-01T10:00:00+00:00",
            },
          ]);
        },
      },
    });

    const movements = await inventory
      .movements({
        organizationId: "org",
        variantId: "v1",
        documentType: "order",
        limit: 20,
      })
      .orThrow();

    expect(movements[0]).toMatchObject({ id: "m1", quantity: "-2" });
    expect(calls).toEqual([
      {
        fn: "list_inventory_movements",
        args: {
          tenant: "org",
          variant: "v1",
          location: null,
          bin: null,
          lot: null,
          document_type: "order",
          document_id: null,
          row_limit: 20,
          row_offset: null,
        },
      },
    ]);
  });
});
