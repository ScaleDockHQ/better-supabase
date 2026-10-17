import { describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../../src/sql/module-types.ts";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (names: readonly string[], layout: ModuleLayout = {}): string =>
  renderModules([...names], layout)
    .filter((file) => file.module === "orders")
    .map((file) => file.contents)
    .join("\n");

const SEQUENCES: ModuleLayout = {
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
