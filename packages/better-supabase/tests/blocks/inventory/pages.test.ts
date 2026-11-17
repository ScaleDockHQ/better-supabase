import { describe, expect, it } from "vitest";

import { createInventory } from "../../../src/blocks/inventory/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const level = {
  id: "v1:l1",
  variantId: "v1",
  locationId: "l1",
  onHand: "4.000000",
  allocated: "1.000000",
  available: "3.000000",
  incoming: "0.000000",
  reorderPoint: null,
  status: "in_stock",
};

const movement = {
  id: "m1",
  kind: "stock.receipt",
  variantId: "v1",
  productId: "p1",
  locationId: "l1",
  binId: null,
  lotId: null,
  quantity: "4",
  unit: null,
  reason: "receipt",
  note: null,
  actorId: "u1",
  documentType: null,
  documentId: null,
  effectiveAt: "2027-01-01T00:00:00Z",
};

const lot = {
  id: "lot1:l1:",
  lotId: "lot1",
  code: "BEANS-1",
  variantId: "v1",
  locationId: "l1",
  binId: null,
  expiresOn: "2027-02-01",
  onHand: "9.000000",
  expiry: "soon",
};

describe("inventory pages", () => {
  it("pages levels with the organization of the call", async () => {
    const transport = fieldsTransport({
      page_inventory_levels: () => ({ items: [level], hasMore: false }),
    });

    const inventory = createInventory({ transport });

    const page = await inventory
      .levelPage({ organizationId: "org-1", q: "v1", limit: 1 })
      .orThrow();

    expect(page.items).toEqual([level]);
    expect(transport.calls[0]).toEqual([
      "page_inventory_levels",
      {
        tenant: "org-1",
        filters: expect.objectContaining({ search: "v1", limit: 1 }),
      },
    ]);
  });

  it("reads one level, movement and lot by id", async () => {
    const inventory = createInventory({
      transport: fieldsTransport({
        get_inventory_level: () => level,
        get_inventory_movement: () => movement,
        get_inventory_lot: () => lot,
      }),
    });

    expect(await inventory.getLevel("v1:l1").orThrow()).toEqual(level);
    expect(await inventory.getMovement("m1").orThrow()).toEqual(movement);
    expect(await inventory.getLot("lot1:l1:").orThrow()).toEqual(lot);
  });

  it("rejects a malformed row instead of passing it on", async () => {
    const inventory = createInventory({
      transport: fieldsTransport({
        get_inventory_lot: () => ({ ...lot, onHand: 9 }),
      }),
    });

    const result = await inventory.getLot("lot1:l1:");

    expect(result.ok).toBe(false);
  });

  it("pages movements and lots", async () => {
    const inventory = createInventory({
      transport: fieldsTransport({
        page_inventory_movements: () => ({ items: [movement], hasMore: false }),
        page_inventory_lots: () => ({ items: [lot], hasMore: false }),
      }),
    });

    const movements = await inventory
      .movementPage({ organizationId: "org-1" })
      .orThrow();

    const lots = await inventory.lotPage({ organizationId: "org-1" }).orThrow();

    expect(movements.items).toEqual([movement]);
    expect(lots.items).toEqual([lot]);
  });

  it("pages locations, bins and variants with q and list filters", async () => {
    const location = {
      id: "l1",
      code: "MAIN",
      name: "Main",
      kind: "warehouse",
      active: true,
    };

    const bin = {
      id: "b1",
      locationId: "l1",
      code: "A-1",
      name: null,
      hold: false,
      active: true,
    };

    const variant = { id: "v1", productId: "p1", sku: "BEAN", title: null };

    const transport = fieldsTransport({
      page_stock_locations: () => ({ items: [location], hasMore: false }),
      page_stock_bins: () => ({ items: [bin], hasMore: false }),
      page_stock_variants: () => ({ items: [variant], hasMore: false }),
    });

    const inventory = createInventory({ transport });

    const locations = await inventory
      .locationPage({
        organizationId: "org-1",
        q: "main",
        filters: { active: ["true"] },
        sort: { by: "name" },
      })
      .orThrow();

    const bins = await inventory
      .binPage({ organizationId: "org-1", filters: { locationId: ["l1"] } })
      .orThrow();

    const variants = await inventory
      .variantPage({ organizationId: "org-1", q: "bean" })
      .orThrow();

    expect(locations.items).toEqual([location]);
    expect(bins.items).toEqual([bin]);
    expect(variants.items).toEqual([variant]);
    expect(transport.calls[0]).toEqual([
      "page_stock_locations",
      {
        tenant: "org-1",
        filters: expect.objectContaining({
          search: "main",
          active: ["true"],
          sort: "name",
        }),
      },
    ]);
  });

  it("refuses a filter a lookup list does not declare", async () => {
    const inventory = createInventory({ transport: fieldsTransport({}) });

    const result = await inventory.variantPage({
      organizationId: "org-1",
      filters: { color: ["red"] },
    });

    expect(result.error?.kind).toBe("invalid_input");
  });
});
