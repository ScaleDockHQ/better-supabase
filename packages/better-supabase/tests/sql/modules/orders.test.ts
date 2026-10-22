import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import {
  customContracts,
  moduleTopics,
  renderBlocks,
} from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[], layout: BlockSqlLayout = {}): string =>
  renderBlocks([...names], layout)
    .filter((file) => file.module === "orders")
    .map((file) => file.contents)
    .join("\n");

const SEQUENCES: BlockSqlLayout = {
  modules: {
    "number-sequences": {
      options: {
        entities: {
          order: { period: "year", format: "SO-{yyyy}-{n:5}" },
          invoice: { period: "none", format: "INV-{n:6}" },
        },
      },
    },
  },
};

describe("orders module", () => {
  it("prices carts from the catalog and keeps checkout service only", () => {
    const sql = sqlOf(["catalog", "orders"]);
    expect(sql).toContain(`references "better_supabase"."product_variants"`);

    for (const fn of [
      "place_order",
      "record_payment",
      "complete_refund",
      "expire_orders",
      "merge_carts",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `grant execute on function "better_supabase"\\."${fn}"\\([^)]*\\) to service_role;`,
        ),
      );
      expect(sql).not.toMatch(
        new RegExp(
          `grant execute on function "better_supabase"\\."${fn}"\\([^)]*\\) to authenticated`,
        ),
      );
    }
  });

  it("reserves stock and writes movements only when inventory is installed", () => {
    expect(sqlOf(["catalog", "orders"])).not.toContain("reserve_stock");
    const sql = sqlOf(["catalog", "inventory", "orders"]);
    expect(sql).toContain("reserve_stock");
    expect(sql).toContain("commit_reservation");
  });

  it("numbers orders and invoices from number-sequences when it numbers them", () => {
    const fallback = sqlOf(["catalog", "orders"]);
    expect(fallback).not.toContain("next_number");
    const sql = sqlOf(["catalog", "number-sequences", "orders"], SEQUENCES);
    expect(sql).toContain("next_number");
    expect(sql).toContain("SO-{yyyy}-{n:5}");
  });

  it("records subject events through the outbox", () => {
    const sql = sqlOf(["catalog", "outbox", "orders"]);

    for (const type of ["order.placed", "order.paid", "order.refunded"]) {
      expect(sql).toContain(`'${type}'`);
    }

    expect(sqlOf(["catalog", "orders"])).not.toContain("'order.placed'");
  });

  it("checks the payment window option", () => {
    expect(
      sqlOf(["catalog", "orders"], {
        modules: { orders: { options: { paymentWindowMinutes: 90 } } },
      }),
    ).toContain("interval '90 minutes'");
    expect(() =>
      sqlOf(["catalog", "orders"], {
        modules: { orders: { options: { paymentWindowMinutes: 0 } } },
      }),
    ).toThrow(/paymentWindowMinutes/);
  });
});

describe("orders module, kitchen", () => {
  const KITCHEN: BlockSqlLayout = {
    modules: { orders: { options: { kitchen: true } } },
  };

  it("owns the kitchen topic only with the option", () => {
    expect(moduleTopics(["catalog", "orders"])).toEqual([]);
    expect(moduleTopics(["catalog", "orders"], KITCHEN)).toEqual([
      { module: "orders", topic: "kitchen:{organizationId}" },
    ]);
  });

  it("adds nothing by default", () => {
    const sql = sqlOf(["catalog", "orders"]);
    expect(sql).not.toContain("order_line_preparations");
    expect(sql).not.toContain("kitchen_stations");
  });

  it("adds stations, routes and line states with indexed keys", () => {
    const sql = sqlOf(["catalog", "orders"], KITCHEN);

    for (const table of [
      "kitchen_stations",
      "kitchen_routes",
      "order_line_preparations",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }

    for (const index of [
      "kitchen_routes_station_idx",
      "order_line_preparations_order_idx",
      "order_line_preparations_station_idx",
    ]) {
      expect(sql).toContain(`create index if not exists ${index}`);
    }

    expect(sql).toContain(`references "better_supabase"."products" ("id")`);
    expect(sql).toContain(
      "check (\"state\" in ('queued', 'preparing', 'ready', 'served'))",
    );
    expect(sql).toContain("better_supabase.tenant_ids_with('orders.prepare')");
  });

  it("broadcasts each change on the tenant's kitchen topic", () => {
    const sql = sqlOf(["catalog", "orders"], KITCHEN);
    expect(sql).toContain("realtime.send(");
    expect(sql).toContain("'kitchen:' || new.\"tenant_id\"::text");
    expect(sql).toContain("like 'kitchen:%'");
  });

  it("emits prepared and served once per order with outbox installed", () => {
    expect(sqlOf(["catalog", "orders"], KITCHEN)).not.toContain(
      "'order.prepared'",
    );
    const sql = sqlOf(["catalog", "outbox", "orders"], KITCHEN);
    expect(sql).toContain("'order.prepared'");
    expect(sql).toContain("'order.served'");
    expect(sql).toContain("'order.prepared:' || v_order.id::text");
  });

  it("lists the kitchen functions in the contract only when on", () => {
    const names = (options: Record<string, unknown>) =>
      customContracts(["catalog", "orders"], {
        modules: { orders: { mode: "custom", options } },
      })
        .find((contract) => contract.module === "orders")
        ?.functions.map((fn) => fn.name);

    expect(names({})).not.toContain("send_order_to_kitchen");
    expect(names({ kitchen: true })).toEqual(
      expect.arrayContaining([
        "save_kitchen_station",
        "send_order_to_kitchen",
        "set_line_preparation",
        "bump_kitchen_ticket",
        "kitchen_queue",
        "order_board",
      ]),
    );
  });
});
