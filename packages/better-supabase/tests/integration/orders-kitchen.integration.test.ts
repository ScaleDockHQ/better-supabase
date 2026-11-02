import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";
import type { Result } from "../../src/core/result.ts";

import { createOrders, sqlTransport } from "../../src/blocks/orders/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "catalog", "outbox", "orders"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("orders kitchen", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("routes lines to stations, moves them through the kitchen and emits once", async () => {
    const s = await BlockSession.open(pool);

    /** Each call in a savepoint, so a raised error keeps the transaction. */
    const transport = (role: () => Promise<void>): BlockTransport => {
      const inner = sqlTransport(s.sql);

      return {
        async call(schema, fn, args) {
          await role();
          await s.client.query("savepoint kitchen_call");

          try {
            const value = await inner.call(schema, fn, args);
            await s.client.query("release savepoint kitchen_call");

            return value;
          } catch (cause) {
            await s.client.query("rollback to savepoint kitchen_call");
            throw cause;
          }
        },
      };
    };

    try {
      const owner = await s.user("kitchen-owner");
      const viewer = await s.user("kitchen-viewer");
      const stranger = await s.user("kitchen-stranger");
      await s.install(MODULES, {
        modules: { orders: { options: { kitchen: true } } },
      });
      const org = await s.organization(owner, { viewer });
      const other = await s.organization(stranger);

      await s.as(owner);

      const product = async (title: string): Promise<string> =>
        (
          await s.value<{ id: string }>(
            "better_supabase.save_product($1, null, $2, null, null, 'physical')",
            [org, title],
          )
        ).id;

      const burger = await product("Burger");
      const fries = await product("Fries");
      const lemonade = await product("Lemonade");

      await s.service();

      const [order] = await s.rows<{ id: string }>(
        `insert into better_supabase.orders (tenant_id, number, sequence, status, currency, customer_id)
         values ($1, 'SO-1', 1, 'paid', 'EUR', $2) returning id`,
        [org, owner.id],
      );

      const orderId = order!.id;

      const lines = await s.rows<{ id: string; title: string }>(
        `insert into better_supabase.order_lines (tenant_id, order_id, position, product_id, sku, title, quantity)
         values ($1, $2, 1, $3, 'B', 'Burger', 2), ($1, $2, 2, $4, 'F', 'Fries', 1), ($1, $2, 3, $5, 'L', 'Lemonade', 1)
         returning id, title`,
        [org, orderId, burger, fries, lemonade],
      );

      const line = (title: string): string =>
        lines.find((row) => row.title === title)!.id;

      const kitchen = createOrders({
        transport: transport(() => s.as(owner)),
      }).kitchen;

      const viewing = createOrders({
        transport: transport(() => s.asRole(viewer)),
      }).kitchen;

      const outsider = createOrders({
        transport: transport(() => s.asRole(stranger)),
      }).kitchen;

      const grill = await kitchen
        .saveStation({
          organizationId: org,
          input: {
            key: "grill",
            name: "Grill",
            position: 1,
            productIds: [burger],
          },
        })
        .orThrow();

      const pass = await kitchen
        .saveStation({
          organizationId: org,
          input: { key: "pass", name: "Pass", default: true },
        })
        .orThrow();

      const bar = await kitchen
        .saveStation({
          organizationId: org,
          input: { key: "bar", name: "Bar", productIds: [lemonade] },
        })
        .orThrow();

      expect(grill).toMatchObject({
        key: "grill",
        isDefault: false,
        active: true,
        productIds: [burger],
      });
      expect(
        hint(
          await kitchen.saveStation({
            organizationId: org,
            input: { key: "x", productIds: ["nope"] },
          }),
        ),
      ).not.toBe("ok");
      expect(
        hint(
          await kitchen.saveStation({
            organizationId: other,
            input: { key: "theirs", name: "No" },
          }),
        ),
      ).toBe("ORDERS_FORBIDDEN");
      expect(
        hint(
          await kitchen.saveStation({
            organizationId: org,
            input: { name: "Gone" },
            stationId: crypto.randomUUID(),
          }),
        ),
      ).toBe("ORDERS_KITCHEN_STATION_NOT_FOUND");

      const renamed = await kitchen
        .saveStation({
          organizationId: org,
          input: { name: "Bar & drinks", default: true },
          stationId: bar.id,
        })
        .orThrow();

      expect(renamed).toMatchObject({ name: "Bar & drinks", isDefault: true });
      await kitchen
        .saveStation({
          organizationId: org,
          input: { default: true },
          stationId: pass.id,
        })
        .orThrow();

      expect(
        (await kitchen.stations(org).orThrow()).map((station) => [
          station.key,
          station.isDefault,
        ]),
      ).toEqual([
        ["bar", false],
        ["pass", true],
        ["grill", false],
      ]);

      expect(
        await kitchen
          .send({ orderId, notes: { [line("Burger")]: "  no onions " } })
          .orThrow(),
      ).toBe(3);
      expect(await kitchen.send({ orderId }).orThrow()).toBe(0);

      const grillQueue = await kitchen
        .queue({ organizationId: org, query: { stationId: grill.id } })
        .orThrow();

      expect(grillQueue).toHaveLength(1);
      expect(grillQueue[0]).toMatchObject({ orderId, number: "SO-1" });
      expect(grillQueue[0]!.lines).toMatchObject([
        {
          title: "Burger",
          sku: "B",
          quantity: 2,
          state: "queued",
          note: "no onions",
          stationId: grill.id,
        },
      ]);
      const all = await kitchen.queue({ organizationId: org }).orThrow();
      expect(all[0]!.lines.map((item) => [item.title, item.stationId])).toEqual(
        [
          ["Burger", grill.id],
          ["Fries", pass.id],
          ["Lemonade", bar.id],
        ],
      );

      const preparing = await kitchen
        .setState({ lineId: line("Burger"), state: "preparing" })
        .orThrow();

      expect(preparing.state).toBe("preparing");
      expect(preparing.startedAt).toBeDefined();
      expect(preparing.readyAt).toBeUndefined();
      expect(
        hint(
          await kitchen.setState({
            lineId: line("Burger"),
            state: "burnt" as "ready",
          }),
        ),
      ).toBe("ORDERS_PREPARATION_STATE_INVALID");
      expect(
        hint(
          await kitchen.setState({
            lineId: crypto.randomUUID(),
            state: "ready",
          }),
        ),
      ).toBe("ORDERS_PREPARATION_NOT_FOUND");
      expect(
        hint(
          await viewing.setState({ lineId: line("Burger"), state: "ready" }),
        ),
      ).toBe("ORDERS_FORBIDDEN");
      expect(hint(await outsider.bump({ orderId, state: "ready" }))).toBe(
        "ORDERS_FORBIDDEN",
      );
      expect(await outsider.queue({ organizationId: org }).orThrow()).toEqual(
        [],
      );

      expect(
        await kitchen
          .bump({ orderId, state: "ready", stationId: bar.id })
          .orThrow(),
      ).toBe(1);
      expect(await kitchen.bump({ orderId, state: "ready" }).orThrow()).toBe(2);
      expect(await kitchen.bump({ orderId, state: "ready" }).orThrow()).toBe(0);

      const back = await kitchen
        .setState({ lineId: line("Fries"), state: "preparing" })
        .orThrow();

      expect(back.readyAt).toBeUndefined();
      await kitchen
        .setState({ lineId: line("Fries"), state: "ready" })
        .orThrow();

      const [board] = await kitchen.board({ organizationId: org }).orThrow();
      expect(board).toMatchObject({
        orderId,
        number: "SO-1",
        customerId: owner.id,
        status: "paid",
        state: "ready",
        counts: { queued: 0, preparing: 0, ready: 3, served: 0 },
      });
      expect(board!.readyAt).toBeDefined();
      expect(board!.servedAt).toBeUndefined();

      expect(await kitchen.bump({ orderId, state: "served" }).orThrow()).toBe(
        3,
      );
      expect(
        await kitchen
          .board({
            organizationId: org,
            query: { since: Temporal.Now.instant().add({ hours: 1 }) },
          })
          .orThrow(),
      ).toEqual([]);
      expect(
        (
          await kitchen
            .queue({ organizationId: org, query: { states: ["served"] } })
            .orThrow()
        )[0]!.lines,
      ).toHaveLength(3);
      expect(await kitchen.queue({ organizationId: org }).orThrow()).toEqual(
        [],
      );

      await s.service();

      const events = await s.rows<{ type: string }>(
        `select type from better_supabase.outbox_events
         where subject = $1 and type in ('order.prepared', 'order.served') order by type`,
        [`orders/${orderId}`],
      );

      expect(events.map((row) => row.type)).toEqual([
        "order.prepared",
        "order.served",
      ]);

      await s.asRole(viewer);
      expect(
        await s.rows(
          "select 1 from better_supabase.order_line_preparations where order_id = $1",
          [orderId],
        ),
      ).toHaveLength(0);

      await s.service();
      await s.client.query(
        "update better_supabase.orders set status = 'cancelled' where id = $1",
        [orderId],
      );
      expect(hint(await kitchen.send({ orderId }))).toBe(
        "ORDERS_KITCHEN_CLOSED",
      );
      expect(hint(await kitchen.send({ orderId: crypto.randomUUID() }))).toBe(
        "ORDERS_ORDER_NOT_FOUND",
      );
      expect(await kitchen.deleteStation(grill.id).orThrow()).toBe(true);
      expect(await kitchen.deleteStation(grill.id).orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });
});
