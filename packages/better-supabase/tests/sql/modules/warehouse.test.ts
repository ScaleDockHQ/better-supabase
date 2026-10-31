import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { WAREHOUSE } from "../../../src/sql/modules/warehouse.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = [
  "memberships",
  "permissions",
  "catalog",
  "ledger",
  "inventory",
  "warehouse",
];

const sqlOf = (blocks: readonly string[] = BASE, layout: Layout = {}): string =>
  renderBlocks(blocks, layout)
    .filter((file) => file.module === "warehouse")
    .map((file) => file.contents)
    .join("\n");

describe("warehouse module", () => {
  it("renders the tables and the states", () => {
    const sql = sqlOf();

    expect(sql).toContain("pick_waves");
    expect(sql).toContain("pick_lists");
    expect(sql).toContain("pick_lines");
    expect(sql).toContain("count_plans");
    expect(sql).toContain("'draft', 'released', 'completed', 'cancelled'");
  });

  it("makes no work items without the tasks block", () => {
    expect(sqlOf()).not.toContain("create_task");
  });

  it("makes picking work items with the tasks block", () => {
    const sql = sqlOf([
      ...BASE.slice(0, -1),
      "tasks",
      "relations",
      "warehouse",
    ]);

    expect(sql).toContain("create_task");
    expect(sql).toContain("created_from");
  });

  it("holds a count over the variance limit for approval", () => {
    const sql = sqlOf();

    expect(sql).toContain("WAREHOUSE_VARIANCE_OVER_LIMIT");
    expect(sql).toContain("post_stock_count");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { warehouse: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(WAREHOUSE.build(context, {})).toBe("");
    const [contract] = customContracts(["warehouse"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_pick_list",
        "record_pick",
        "post_cycle_count",
      ]),
    );
  });
});
