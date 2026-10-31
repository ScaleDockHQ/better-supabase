import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { MAINTENANCE } from "../../../src/sql/modules/maintenance.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = [
  "memberships",
  "permissions",
  "subjects",
  "dispatch",
  "maintenance",
];

const sqlOf = (layout: Layout = {}): string =>
  renderBlocks(BASE, layout)
    .filter((file) => file.module === "maintenance")
    .map((file) => file.contents)
    .join("\n");

describe("maintenance module", () => {
  it("renders the tables and the plan kind check", () => {
    const sql = sqlOf();

    expect(sql).toContain("maintenance_plans");
    expect(sql).toContain("maintenance_plan_parts");
    expect(sql).toContain("maintenance_meters");
    expect(sql).toContain("maintenance_meter_readings");
    expect(sql).toContain("maintenance_calibrations");
    expect(sql).toContain("'time', 'meter'");
  });

  it("opens dispatch work orders with the plan's parts and follows their status", () => {
    const sql = sqlOf();

    expect(sql).toContain("create_work_order");
    expect(sql).toContain("record_work_order_part");
    expect(sql).toContain("maintenance_work_order_closed");
    expect(sql).toContain("bsb_maintenance_work_order");
  });

  it("refuses a reading below the previous one", () => {
    expect(sqlOf()).toContain("a reading is not below the previous one");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { maintenance: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(MAINTENANCE.build(context, {})).toBe("");
    const [contract] = customContracts(["maintenance"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "create_maintenance_plan",
        "generate_maintenance_work_orders",
        "record_meter_reading",
        "record_calibration",
      ]),
    );
  });
});
