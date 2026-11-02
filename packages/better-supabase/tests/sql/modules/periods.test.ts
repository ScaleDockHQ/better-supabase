import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { PERIODS } from "../../../src/sql/modules/periods.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "periods"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "periods")
    .map((file) => file.contents)
    .join("\n");

describe("periods module", () => {
  it("renders the table, the statuses and one range per kind and start", () => {
    const sql = sqlOf();

    expect(sql).toContain("'open', 'locked', 'closed'");
    expect(sql).toMatch(/unique \("tenant_id", "kind", "starts_on"\)/);
    expect(sql).toContain("PERIOD_OVERLAP");
  });

  it("has no blockers or on-close steps without a contributing block", () => {
    const sql = sqlOf();

    expect(sql).toContain("No installed block adds blockers.");
    expect(sql).toContain("No installed block adds an on-close step.");
  });

  it("asks the blockers of an installed block and runs its on-close step", () => {
    const sql = sqlOf([...BASE, "accounting"]);

    expect(sql).toContain("v_row.\"kind\" = 'fiscal_period'");
    expect(sql).toContain("accounting_range_close_blockers");
    expect(sql).toContain("accounting_close_range");
  });

  it("creates a leave year in calendar years when leave is installed", () => {
    const sql = sqlOf([...BASE, "approvals", "ledger", "leave"]);

    expect(sql).toContain("'leave_year'");
    expect(sql).toContain("date_trunc('year'");
    expect(sql).toContain("leave_close_range");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { periods: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(PERIODS.build(context, {})).toBe("");
    const [contract] = customContracts(["periods"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining(["create_period", "period_for", "close_period"]),
    );
  });
});
