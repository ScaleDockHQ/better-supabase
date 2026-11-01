import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createInventory } from "../../src/blocks/inventory/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

interface Level {
  readonly on_hand: number;
  readonly reserved: number;
  readonly incoming: number;
  readonly available: number;
}

describe.skipIf(!live)("inventory module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let tenant: string;
  let warehouse: string;
  let store: string;
  let tee: string;
  let mug: string;
  let preorder: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  const level = async (variant: string, location: string): Promise<Level> => {
    const [row] = await session.rows<Level>(
      "select on_hand::float8 as on_hand, reserved::float8 as reserved, incoming::float8 as incoming, available::float8 as available from better_supabase.stock_levels where variant_id = $1 and location_id = $2",
      [variant, location],
    );

    return row ?? { on_hand: 0, reserved: 0, incoming: 0, available: 0 };
  };

  const variant = async (sku: string, backorder = false): Promise<string> => {
    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, $2, null, null, 'physical')",
      [tenant, sku],
    );

    const saved = await call<{ id: string }>(
      "better_supabase.save_variant($1, null, $2, '{}'::uuid[], null, null, null, true, $3)",
      [product.id, sku, backorder],
    );

    return saved.id;
  };

  const location = async (code: string): Promise<string> =>
    (
      await call<{ id: string }>(
        "better_supabase.save_location($1, null, $2, $2, 'warehouse')",
        [tenant, code],
      )
    ).id;

  const events = async (type: string): Promise<Record<string, unknown>[]> =>
    (
      await session.rows<{ data: Record<string, unknown> }>(
        "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = $2 order by position",
        [tenant, type],
      )
    ).map((row) => row.data);

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(["organizations", "catalog", "inventory", "outbox"]);
    owner = await session.user("inventory-owner");
    member = await session.user("inventory-member");
    tenant = await session.organization(owner, { member });
    await session.as(owner);
    warehouse = await location("WH-1");
    store = await location("STORE-1");
    tee = await variant("TEE");
    mug = await variant("MUG");
    preorder = await variant("PRE", true);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("keeps levels from the ledger and refuses to go below zero", async () => {
    await session.as(owner);

    const added = await call<{ onHand: number; available: number }>(
      "better_supabase.adjust_stock($1, $2, 10, 'receipt', 'first delivery')",
      [tee, warehouse],
    );

    expect(added).toMatchObject({ onHand: 10, available: 10 });
    await call("better_supabase.adjust_stock($1, $2, -2, 'damage', null)", [
      tee,
      warehouse,
    ]);
    expect(await level(tee, warehouse)).toMatchObject({
      on_hand: 8,
      available: 8,
    });
    expect(
      await session.hint(
        "better_supabase.adjust_stock($1, $2, -9, 'loss', null)",
        [tee, warehouse],
      ),
    ).toBe("INVENTORY_INSUFFICIENT");
    expect(
      await session.hint(
        "better_supabase.adjust_stock($1, $2, 1, 'sale', null)",
        [tee, warehouse],
      ),
    ).toBe("INVENTORY_REASON_INVALID");
    await call("better_supabase.adjust_stock($1, $2, -3, 'adjustment', null)", [
      preorder,
      warehouse,
    ]);
    expect(await level(preorder, warehouse)).toMatchObject({ on_hand: -3 });
    expect((await events("stock.adjusted")).at(-1)).toMatchObject({
      quantity: "-3",
      reason: "adjustment",
    });
  });

  it("keeps the ledger append-only", async () => {
    await session.service();
    expect(
      await session.hint(
        "update better_supabase.ledger_entries set amount = 100 where account_id in (select id from better_supabase.ledger_accounts where holder_id = $1::text)",
        [tee],
      ),
    ).toBe("LEDGER_APPEND_ONLY");
    await session.as(owner);
  });

  it("sets on-hand from a count and writes the difference", async () => {
    await session.as(owner);

    const counted = await call<{ delta: number; onHand: number }>(
      "better_supabase.count_stock($1, $2, 5, 'cycle count')",
      [tee, warehouse],
    );

    expect(counted).toMatchObject({ delta: -3, onHand: 5 });

    const unchanged = await call<{ delta: number; movementId: string | null }>(
      "better_supabase.count_stock($1, $2, 5, null)",
      [tee, warehouse],
    );

    expect(unchanged).toEqual({ delta: 0, movementId: null, onHand: 5 });
  });

  it("reserves, commits and releases stock", async () => {
    await session.as(owner);

    const held = await call<{ id: string; available: number }>(
      "better_supabase.reserve_stock($1, $2, 2, 'cart', 'c1', null)",
      [tee, warehouse],
    );

    expect(held.available).toBe(3);
    expect(
      await session.hint(
        "better_supabase.reserve_stock($1, $2, 4, 'cart', 'c2', null)",
        [tee, warehouse],
      ),
    ).toBe("INVENTORY_INSUFFICIENT");

    const committed = await call<{ movementId: string }>(
      "better_supabase.commit_reservation($1)",
      [held.id],
    );

    expect(committed.movementId).toBeTruthy();
    expect(await level(tee, warehouse)).toMatchObject({
      on_hand: 3,
      reserved: 0,
      available: 3,
    });
    expect(
      await session.hint("better_supabase.commit_reservation($1)", [held.id]),
    ).toBe("INVENTORY_RESERVATION_CLOSED");

    const second = await call<{ id: string }>(
      "better_supabase.reserve_stock($1, $2, 1, 'cart', 'c3', null)",
      [tee, warehouse],
    );

    expect(
      await call<boolean>("better_supabase.release_reservation($1)", [
        second.id,
      ]),
    ).toBe(true);
    expect(
      await call<boolean>("better_supabase.release_reservation($1)", [
        second.id,
      ]),
    ).toBe(false);
    expect(await level(tee, warehouse)).toMatchObject({ reserved: 0 });
  });

  it("expires reservations from the service job and lazily on the next reserve", async () => {
    await session.as(owner);

    const first = await call<{ id: string }>(
      "better_supabase.reserve_stock($1, $2, 3, 'cart', 'c4', null)",
      [tee, warehouse],
    );

    await session.service();
    await session.rows(
      "update better_supabase.stock_reservations set expires_at = now() - interval '1 second' where id = $1",
      [first.id],
    );
    await session.as(owner);

    const next = await call<{ id: string; available: number }>(
      "better_supabase.reserve_stock($1, $2, 3, 'cart', 'c5', null)",
      [tee, warehouse],
    );

    expect(next.available).toBe(0);
    await session.service();
    await session.rows(
      "update better_supabase.stock_reservations set expires_at = now() - interval '1 second' where id = $1",
      [next.id],
    );
    expect(
      await call<number>("better_supabase.expire_reservations(null)"),
    ).toBe(1);
    expect(await level(tee, warehouse)).toMatchObject({
      reserved: 0,
      available: 3,
    });
    expect(
      (await events("reservation.released")).map((data) => data["reason"]),
    ).toEqual(["released", "expired"]);
    await session.as(owner);
  });

  it("fires stock.reorder_point_reached when available drops to the reorder point", async () => {
    await session.as(owner);
    await call("better_supabase.adjust_stock($1, $2, 10, 'receipt', null)", [
      mug,
      warehouse,
    ]);
    await call("better_supabase.set_reorder_point($1, $2, 4)", [
      mug,
      warehouse,
    ]);
    await call("better_supabase.adjust_stock($1, $2, -5, 'loss', null)", [
      mug,
      warehouse,
    ]);
    expect(await events("stock.reorder_point_reached")).toEqual([]);
    await call("better_supabase.reserve_stock($1, $2, 1, 'cart', 'c6', null)", [
      mug,
      warehouse,
    ]);
    expect(await events("stock.reorder_point_reached")).toEqual([
      expect.objectContaining({
        subjectType: "product_variant",
        subjectId: mug,
        available: "4.000000",
        reorderPoint: "4.000000",
      }),
    ]);
  });

  it("moves stock between locations with a transfer", async () => {
    await session.as(owner);

    const transfer = await call<{ id: string; status: string }>(
      "better_supabase.create_transfer($1, $2, $3, $4::jsonb, null)",
      [
        tenant,
        warehouse,
        store,
        JSON.stringify([{ variantId: mug, quantity: 2 }]),
      ],
    );

    expect(transfer.status).toBe("draft");
    expect(
      await session.hint(
        "better_supabase.create_transfer($1, $2, $2, $3::jsonb, null)",
        [tenant, warehouse, JSON.stringify([{ variantId: mug, quantity: 2 }])],
      ),
    ).toBe("INVENTORY_TRANSFER_SAME_LOCATION");
    expect(
      await session.hint(
        "better_supabase.create_transfer($1, $2, $3, $4::jsonb, null)",
        [
          tenant,
          warehouse,
          store,
          JSON.stringify([{ variantId: mug, quantity: 0 }]),
        ],
      ),
    ).toBe("INVENTORY_LINES_INVALID");
    await call("better_supabase.ship_transfer($1)", [transfer.id]);
    expect(await level(mug, warehouse)).toMatchObject({ on_hand: 3 });
    expect(
      await session.hint("better_supabase.ship_transfer($1)", [transfer.id]),
    ).toBe("INVENTORY_TRANSFER_STATUS");
    await call("better_supabase.receive_transfer($1)", [transfer.id]);
    expect(await level(mug, store)).toMatchObject({ on_hand: 2 });

    const back = await call<{ id: string }>(
      "better_supabase.create_transfer($1, $2, $3, $4::jsonb, null)",
      [
        tenant,
        store,
        warehouse,
        JSON.stringify([{ variantId: mug, quantity: 1 }]),
      ],
    );

    await call("better_supabase.ship_transfer($1)", [back.id]);
    await call("better_supabase.cancel_transfer($1)", [back.id]);
    expect(await level(mug, store)).toMatchObject({ on_hand: 2 });
  });

  it("receives a purchase order in parts and keeps the rest on backorder", async () => {
    await session.as(owner);

    const lines = JSON.stringify([
      { variantId: tee, quantity: 10, unitCost: "450" },
      { variantId: mug, quantity: 4, unitCost: "300" },
    ]);

    const order = await call<{ id: string }>(
      "better_supabase.save_purchase_order($1, null, $2, 'company', 'acme-supplies', 'EUR', null, $3::jsonb, null)",
      [tenant, warehouse, lines],
    );

    expect(
      await session.hint(
        "better_supabase.save_purchase_order($1, null, $2, 'company', null, 'EUR', null, $3::jsonb, null)",
        [tenant, warehouse, lines],
      ),
    ).toBe("INVENTORY_SUPPLIER_INVALID");
    expect(
      await session.hint(
        "better_supabase.save_purchase_order($1, null, $2, null, null, 'EUX', null, $3::jsonb, null)",
        [tenant, warehouse, lines],
      ),
    ).toBe("INVENTORY_CURRENCY_INVALID");
    await call("better_supabase.place_purchase_order($1)", [order.id]);
    expect(await level(tee, warehouse)).toMatchObject({ incoming: 10 });
    expect(
      await session.hint(
        "better_supabase.save_purchase_order($1, $2, $3, null, null, 'EUR', null, $4::jsonb, null)",
        [tenant, order.id, warehouse, lines],
      ),
    ).toBe("INVENTORY_PURCHASE_ORDER_LOCKED");

    const [teeLine, mugLine] = await session.rows<{ id: string }>(
      "select id from better_supabase.purchase_order_lines where purchase_order_id = $1 order by quantity_ordered desc",
      [order.id],
    );

    const partial = await call<{ status: string; backordered: number }>(
      "better_supabase.receive_purchase_order($1, $2::jsonb)",
      [order.id, JSON.stringify([{ lineId: teeLine!.id, quantity: 6 }])],
    );

    expect(partial).toEqual({
      status: "partially_received",
      backordered: 8,
      receiptId: expect.any(String),
    });
    expect(await level(tee, warehouse)).toMatchObject({
      on_hand: 9,
      incoming: 4,
    });
    expect(
      await session.hint(
        "better_supabase.receive_purchase_order($1, $2::jsonb)",
        [order.id, JSON.stringify([{ lineId: teeLine!.id, quantity: 5 }])],
      ),
    ).toBe("INVENTORY_OVER_RECEIPT");

    const done = await call<{ status: string; backordered: number }>(
      "better_supabase.receive_purchase_order($1, $2::jsonb)",
      [
        order.id,
        JSON.stringify([
          { lineId: teeLine!.id, quantity: 4 },
          { lineId: mugLine!.id, quantity: 4 },
        ]),
      ],
    );

    expect(done).toEqual({
      status: "received",
      backordered: 0,
      receiptId: expect.any(String),
    });
    expect(
      await session.hint("better_supabase.cancel_purchase_order($1)", [
        order.id,
      ]),
    ).toBe("INVENTORY_PURCHASE_ORDER_STATUS");

    const cancelled = await call<{ id: string }>(
      "better_supabase.save_purchase_order($1, null, $2, null, null, 'EUR', null, $3::jsonb, null)",
      [
        tenant,
        store,
        JSON.stringify([{ variantId: tee, quantity: 5, unitCost: "450" }]),
      ],
    );

    await call("better_supabase.place_purchase_order($1)", [cancelled.id]);
    expect(await level(tee, store)).toMatchObject({ incoming: 5 });
    await call("better_supabase.cancel_purchase_order($1)", [cancelled.id]);
    expect(await level(tee, store)).toMatchObject({ incoming: 0 });
    expect(
      (await events("purchase_order.received")).map((data) => data["status"]),
    ).toEqual(["partially_received", "received"]);
  });

  it("stops catalog from deleting a variant with stock history", async () => {
    await session.as(owner);
    expect(
      await session.hint("better_supabase.delete_variant($1)", [tee]),
    ).toBe("CATALOG_VARIANT_IN_USE");
    expect(
      await session.hint("better_supabase.delete_location($1)", [warehouse]),
    ).toBe("INVENTORY_LOCATION_IN_USE");
  });

  it("drives the TypeScript block against the SQL", async () => {
    await session.as(owner);
    const inventory = createInventory({ transport: sqlTransport(session.sql) });

    const shelf = await inventory
      .saveLocation({
        organizationId: tenant,
        input: { code: "SHELF", name: "Shelf", kind: "store" },
      })
      .orThrow();

    expect(
      await inventory
        .adjustStock({
          variantId: mug,
          locationId: shelf.id,
          quantity: 4,
          reason: "receipt",
        })
        .orThrow(),
    ).toMatchObject({ onHand: 4, available: 4 });

    const held = await inventory
      .reserve({
        variantId: mug,
        locationId: shelf.id,
        input: { quantity: 3, referenceType: "cart" },
      })
      .orThrow();

    expect(held.available).toBe(1);
    expect(held.expiresAt).toBeInstanceOf(Temporal.Instant);
    expect(
      await inventory.reserve({
        variantId: mug,
        locationId: shelf.id,
        input: { quantity: 2 },
      }),
    ).toMatchObject({ ok: false, error: { hint: "INVENTORY_INSUFFICIENT" } });
    expect(await inventory.releaseReservation(held.id).orThrow()).toBe(true);
  });

  it("lets only permitted members write or read", async () => {
    await session.as(member);
    expect(
      await session.hint(
        "better_supabase.adjust_stock($1, $2, 1, 'receipt', null)",
        [tee, warehouse],
      ),
    ).toBe("INVENTORY_FORBIDDEN");
    expect(
      await session.hint(
        "better_supabase.reserve_stock($1, $2, 1, 'cart', 'm1', null)",
        [tee, warehouse],
      ),
    ).toBe("INVENTORY_FORBIDDEN");
    await session.asRole(member);
    expect(
      await session.rows("select 1 from better_supabase.stock_levels"),
    ).toEqual([]);
    await session.asRole(owner);
    expect(
      (await session.rows("select 1 from better_supabase.stock_levels")).length,
    ).toBeGreaterThan(0);
    await session.as(owner);
  });
});
