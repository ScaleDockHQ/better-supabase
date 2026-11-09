import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

describe("maintenance without dispatch", () => {
  it("installs plans, meters and calibrations and skips work orders", () => {
    const sql = renderBlocks(["maintenance"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("list_maintenance_plans");
    expect(sql).toContain("maintenance_plans");
    expect(sql).not.toContain("generate_maintenance_work_orders");
  });

  it("opens work orders when dispatch is installed", () => {
    const sql = renderBlocks(["maintenance", "dispatch"])
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("generate_maintenance_work_orders");
  });
});
