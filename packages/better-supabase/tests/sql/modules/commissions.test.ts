import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "ledger", "periods", "commissions"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "commissions")
    .map((file) => file.contents)
    .join("\n");

describe("commissions module", () => {
  it("renders the four tables and the accrual functions", () => {
    const sql = sqlOf();

    expect(sql).toContain("commission_plans");
    expect(sql).toContain("commission_statements");
    expect(sql).toContain("accrue_commission");
    expect(sql).toContain("commission_payroll_lines");
  });

  it("adds no invoice trigger unless the option is on", () => {
    expect(sqlOf()).not.toMatch(/trigger[^;]*invoices/i);
  });

  it("renders nothing in custom mode", () => {
    const custom: Layout = { modules: { commissions: { mode: "custom" } } };

    expect(sqlOf(BASE, custom).trim()).toBe("");
  });
});
