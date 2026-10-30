import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { MANUFACTURING } from "../../../src/sql/modules/manufacturing.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = [
  "memberships",
  "permissions",
  "catalog",
  "inventory",
  "numbering",
  "manufacturing",
];

const withModules = (...modules: string[]): string[] => [
  ...BASE.slice(0, -1),
  ...modules,
  "manufacturing",
];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "manufacturing")
    .map((file) => file.contents)
    .join("\n");

describe("manufacturing module", () => {
  it("moves stock through the inventory ledger and numbers orders", () => {
    const sql = sqlOf();

    expect(sql).toContain('"better_supabase"."move_stock"(');
    expect(sql).toContain('"better_supabase"."take_allocation"(');
    expect(sql).toContain("'consumption', 'production_order'");
    expect(sql).toContain("'MO-{yyyy}-{n:4}'");
    expect(sql).toContain(
      'primary key ("parent_lot_id", "child_lot_id", "order_id")',
    );
  });

  it("references assets, drive nodes and inspections only when installed", () => {
    const bare = sqlOf();

    expect(bare).not.toContain('"better_supabase"."assets"');
    expect(bare).not.toContain("drive_nodes");
    expect(bare).not.toContain("schedule_inspection");

    const linked = sqlOf(
      {},
      withModules("subjects", "forms", "assets", "drive", "inspections"),
    );

    expect(linked).toMatch(
      /"asset_id" uuid references "better_supabase"\."assets"/,
    );
    expect(linked).toContain("the asset isn''t an asset of this organization");
    expect(linked).toContain("aren''t a drive node of this organization");
    expect(linked).toContain('"better_supabase"."schedule_inspection"(');
    expect(linked).toMatch(
      /"inspection_id" uuid references "better_supabase"\."inspections"/,
    );
  });

  it("books labor to work in progress only with accounting installed", () => {
    expect(sqlOf()).not.toContain("accounting_production_order_lines");

    const sql = sqlOf({}, withModules("accounting"));

    expect(sql).toContain("accounting_production_order_lines");
    expect(sql).toContain("'work_in_progress'");
    expect(sql).toContain("accounting_post_source\"('production_order'");
  });

  it("turns purchase suggestions into the inventory block's purchase orders", () => {
    const sql = sqlOf();

    expect(sql).toContain('"better_supabase"."save_purchase_order"(');
    expect(sql).toContain("From material requirements");
  });

  it("guards every write with the read-only actor check", () => {
    const sql = sqlOf();

    for (const fn of [
      "save_bom",
      "activate_bom",
      "save_work_center",
      "create_production_order",
      "release_production_order",
      "complete_production_order",
      "cancel_production_order",
      "create_from_requirements",
    ]) {
      const body = sql.slice(sql.indexOf(`"better_supabase"."${fn}"(`));

      expect(body.slice(0, body.indexOf("$$;"))).toContain("ACTOR_READ_ONLY");
    }
  });

  it("adds the extra columns to production orders", () => {
    const sql = sqlOf({
      modules: {
        manufacturing: { options: { extraColumns: { line: "text" } } },
      },
    });

    expect(sql).toContain('"line" text');
    expect(sql).toContain("'fields'");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { manufacturing: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(MANUFACTURING.build(context, {})).toBe("");
    const [contract] = customContracts(["manufacturing"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_bom",
        "activate_bom",
        "explode_bom",
        "create_production_order",
        "complete_production_order",
        "lot_genealogy",
        "material_requirements",
      ]),
    );
  });
});
