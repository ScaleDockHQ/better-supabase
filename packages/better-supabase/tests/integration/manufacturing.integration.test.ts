import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createManufacturing } from "../../src/blocks/manufacturing/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

interface Order {
  readonly id: string;
  readonly number: string;
  readonly status: string;
  readonly outputLotId: string | null;
}

describe.skipIf(!live)("manufacturing module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let tenant: string;
  let warehouse: string;
  let table: string;
  let leg: string;
  let top: string;
  let bom: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  const variant = async (sku: string): Promise<string> => {
    const product = await call<{ id: string }>(
      "better_supabase.save_product($1, null, $2, null, null, 'physical')",
      [tenant, sku],
    );

    return (
      await call<{ id: string }>(
        "better_supabase.save_variant($1, null, $2, '{}'::uuid[], null, null, null, true, false)",
        [product.id, sku],
      )
    ).id;
  };

  const onHand = async (variantId: string): Promise<number> => {
    const [row] = await session.rows<{ on_hand: number }>(
      "select on_hand::float8 as on_hand from better_supabase.stock_levels where variant_id = $1 and location_id = $2",
      [variantId, warehouse],
    );

    return row?.on_hand ?? 0;
  };

  const receive = async (
    variantId: string,
    quantity: number,
    lotCode: string,
  ): Promise<string> => {
    await session.service();

    const lot = await call<string>(
      "better_supabase.stock_lot_for($1, $2, $3, null)",
      [tenant, variantId, lotCode],
    );

    await call(
      "better_supabase.move_stock($1, $2, $3, $4, 'receipt', null, null, null, $5::jsonb)",
      [tenant, variantId, warehouse, quantity, JSON.stringify({ lotId: lot })],
    );
    await session.as(owner);

    return lot;
  };

  const events = async (type: string): Promise<Record<string, unknown>[]> =>
    (
      await session.rows<{ data: Record<string, unknown> }>(
        "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = $2 order by position",
        [tenant, type],
      )
    ).map((row) => row.data);

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install([
      "organizations",
      "outbox",
      "numbering",
      "catalog",
      "inventory",
      "manufacturing",
    ]);
    owner = await session.user("manufacturing-owner");
    member = await session.user("manufacturing-member");
    tenant = await session.organization(owner, { member });
    await session.as(owner);
    warehouse = (
      await call<{ id: string }>(
        "better_supabase.save_location($1, null, 'WH-1', 'WH-1', 'warehouse')",
        [tenant],
      )
    ).id;
    table = await variant("TABLE");
    leg = await variant("LEG");
    top = await variant("TOP");
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("versions a bill of materials and refuses a cycle", async () => {
    await session.as(owner);

    const saved = await call<{ id: string; version: number; status: string }>(
      "better_supabase.save_bom($1, $2, $3::jsonb, null)",
      [
        tenant,
        table,
        JSON.stringify({
          components: [
            { variantId: leg, quantity: 4 },
            { variantId: top, quantity: 1 },
          ],
        }),
      ],
    );

    expect(saved).toMatchObject({ version: 1, status: "draft" });
    expect(
      await session.hint("better_supabase.save_bom($1, $2, $3::jsonb, null)", [
        tenant,
        table,
        JSON.stringify({ components: [{ variantId: table, quantity: 1 }] }),
      ]),
    ).toBe("BOM_CYCLE");
    expect(
      await session.hint("better_supabase.save_bom($1, $2, $3::jsonb, null)", [
        tenant,
        table,
        JSON.stringify({ components: [] }),
      ]),
    ).toBe("BOM_INVALID");
    expect(
      await session.hint(
        "better_supabase.create_production_order($1, $2::jsonb)",
        [tenant, JSON.stringify({ variantId: table, quantity: 1 })],
      ),
    ).toBe("BOM_NOT_ACTIVE");

    const active = await call<{ status: string }>(
      "better_supabase.activate_bom($1)",
      [saved.id],
    );

    expect(active.status).toBe("active");
    bom = saved.id;
    expect(await events("bom.activated")).toHaveLength(1);
  });

  it("releases an order only when the components are in stock", async () => {
    await session.as(owner);

    const order = await call<Order>(
      "better_supabase.create_production_order($1, $2::jsonb)",
      [tenant, JSON.stringify({ variantId: table, quantity: 2 })],
    );

    expect(order.status).toBe("draft");
    expect(order.number).toMatch(/^MO-/u);
    expect(
      await session.hint(
        "better_supabase.release_production_order($1, false)",
        [order.id],
      ),
    ).toBe("PRODUCTION_ORDER_SHORTAGE");
    expect(
      await session.hint(
        "better_supabase.complete_production_order($1, 2, 0, null)",
        [order.id],
      ),
    ).toBe("PRODUCTION_ORDER_STATUS_INVALID");
  });

  it("consumes the components, receives the output and links the lots", async () => {
    const legLot = await receive(leg, 8, "LEG-A");
    const topLot = await receive(top, 2, "TOP-A");

    const manufacturing = createManufacturing({
      transport: sqlTransport(session.sql),
      tenant,
    });

    const [draft] = await manufacturing
      .listOrders({ status: "draft" })
      .orThrow();

    expect(draft).toBeDefined();

    const released = await manufacturing
      .release({ orderId: draft!.id })
      .orThrow();

    expect(released.status).toBe("released");
    expect(released.bomId).toBe(bom);

    const done = await manufacturing
      .complete({ orderId: draft!.id, produced: 2, lot: { code: "TABLE-A" } })
      .orThrow();

    expect(done.status).toBe("done");
    expect(await onHand(leg)).toBe(0);
    expect(await onHand(top)).toBe(0);
    expect(await onHand(table)).toBe(2);
    expect(done.outputLotId).not.toBeNull();

    const tree = await manufacturing
      .lotGenealogy({ lotId: done.outputLotId! })
      .orThrow();

    expect(tree.lots.map((lot) => lot.lotId).toSorted()).toEqual(
      [legLot, topLot].toSorted(),
    );

    const up = await manufacturing
      .lotGenealogy({ lotId: legLot, direction: "up" })
      .orThrow();

    expect(up.lots.map((lot) => lot.lotId)).toEqual([done.outputLotId]);
    expect((await events("production_order.completed")).at(-1)).toMatchObject({
      id: draft!.id,
      producedQuantity: "2.000000",
      status: "done",
    });
  });

  it("lets members read and produce but not plan", async () => {
    await session.as(member);
    expect(
      await session.hint(
        "better_supabase.create_production_order($1, $2::jsonb)",
        [tenant, JSON.stringify({ variantId: table, quantity: 1 })],
      ),
    ).toBe("MANUFACTURING_FORBIDDEN");
    expect(await session.hint("better_supabase.activate_bom($1)", [bom])).toBe(
      "MANUFACTURING_FORBIDDEN",
    );
    await session.asRole(member);
    expect(
      (await session.rows("select 1 from better_supabase.production_orders"))
        .length,
    ).toBeGreaterThan(0);
    await session.as(owner);
  });
});
